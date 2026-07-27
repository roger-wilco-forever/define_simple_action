# frozen_string_literal: true

RSpec.describe DefineSimpleAction::Concern do
  # Минимальный двойник Rails-контроллера — без ActionController, чтобы не тянуть Rails в тесты gem'а.
  let(:controller_class) do
    Class.new do
      include DefineSimpleAction::Concern

      attr_accessor :params, :format_symbol, :rendered, :head_status

      def initialize(params: {}, format_symbol: :json)
        @params = params
        @format_symbol = format_symbol
        @rendered = nil
        @head_status = nil
      end

      def request
        Struct.new(:format).new(Struct.new(:symbol).new(format_symbol))
      end

      def head(status)
        @head_status = status
      end

      def render(**opts)
        @rendered = opts
      end

      # respond_to-двойник: сразу выполняет блок для текущего формата
      def respond_to
        yield(FormatDouble.new(format_symbol))
      end

      class FormatDouble
        def initialize(current_format)
          @current_format = current_format
        end

        def method_missing(format, &block)
          return super unless block

          block.call if format == @current_format
        end

        def respond_to_missing?(_format, _include_private = false)
          true
        end
      end
    end
  end

  let(:service_result_class) { Struct.new(:failure?) }
  let(:service_result) { service_result_class.new(false) }

  let(:index_service_class) do
    result = service_result

    Struct.new(:authorization_data, :model, :notify_data, :validation_contract_name, keyword_init: true) do
      define_method(:call) { |_params| result }
    end
  end

  describe ".define_simple_actions" do
    it "defines only the requested actions" do
      controller_class.define_simple_actions(actions: %i[index show], model_name: "Widget")

      expect(controller_class.instance_methods(false)).to include(:index, :show)
      expect(controller_class.instance_methods(false)).not_to include(:create)
    end

    it "does not override an action already defined in the class" do
      controller_class.class_eval do
        def index
          :custom_index
        end
      end
      controller_class.define_simple_actions(actions: %i[index], model_name: "Widget")

      expect(controller_class.new.index).to eq(:custom_index)
    end
  end

  describe "required hooks" do
    it "raises NotImplementedError for #authorization_data by default" do
      expect { controller_class.new.authorization_data }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for #serialize_for_action by default" do
      expect { controller_class.new.serialize_for_action("index", :result, {}) }.to raise_error(NotImplementedError)
    end
  end

  describe "#define_simple_action dispatch" do
    let(:model_class) { Class.new }

    let(:controller) do
      controller_class.new.tap do |c|
        def c.prefix
          "Widgets"
        end

        def c.authorization_data
          { current_user: :someone }
        end

        def c.serialize_for_action(_name, result, _service_params)
          { data: result }
        end
      end
    end

    before { stub_const("Widgets::IndexService", index_service_class) }

    it "resolves the service by `\#{prefix}::\#{action.camelize}Service` and renders json" do
      controller.define_simple_action("index", model_class, %i[json], nil, false, nil)

      expect(controller.rendered).to eq(json: { data: service_result }, status: :ok)
    end

    it "responds with 406 when the request format is not in response_formats" do
      controller.format_symbol = :xml

      controller.define_simple_action("index", model_class, %i[json], nil, false, nil)

      expect(controller.head_status).to eq(:not_acceptable)
      expect(controller.rendered).to be_nil
    end

    it "falls back to fallback_service_namespace when the per-controller service is missing" do
      stub_const("Base::IndexService", index_service_class)
      def controller.prefix
        "Missing::Namespace"
      end

      def controller.fallback_service_namespace
        "Base"
      end

      controller.define_simple_action("index", model_class, %i[json], nil, false, nil)

      expect(controller.rendered).to eq(json: { data: service_result }, status: :ok)
    end

    it "re-raises NameError when there is no fallback_service_namespace" do
      def controller.prefix
        "Missing::Namespace"
      end

      expect do
        controller.define_simple_action("index", model_class, %i[json], nil, false, nil)
      end.to raise_error(NameError)
    end

    it "passes use_cache/cache_expires_in through to around_action_execution" do
      received = nil
      controller.define_singleton_method(:around_action_execution) do |**kwargs, &block|
        received = kwargs
        block.call
      end

      controller.define_simple_action("index", model_class, %i[json], nil, true, 42)

      expect(received).to include(use_cache: true, cache_expires_in: 42, model_name: model_class)
    end
  end

  describe "#fetch_status_for_action" do
    let(:controller) { controller_class.new }
    let(:failure_result) { Struct.new(:failure?).new(true) }
    let(:success_result) { Struct.new(:failure?).new(false) }

    it "returns :unprocessable_entity when result is a failure" do
      expect(controller.fetch_status_for_action("create", failure_result)).to eq(:unprocessable_entity)
    end

    it "returns the CRUD_ACTION_DATA status otherwise" do
      expect(controller.fetch_status_for_action("create", success_result)).to eq(:created)
    end
  end

  describe "#resource_index_params" do
    it "builds ransack-ready params with default ordering" do
      controller = controller_class.new(params: { q: { title_cont: "foo" }, limit: "10" })

      expect(controller.resource_index_params).to eq(
        limit: "10",
        q: { title_cont: "foo", s: "id asc" }
      )
    end
  end

  describe "#resource_show_params / #resource_show_by_slug_params (dry-transformer deep_symbolize_keys)" do
    it "deep-symbolizes q via dry-transformer when q is present" do
      q = { "with_sites" => "true" }
      q.define_singleton_method(:to_unsafe_h) { q }
      controller = controller_class.new(params: { id: "1", q:, slug: "foo" })

      expect(controller.resource_show_params).to eq(id: 1, q: { with_sites: "true" })
      expect(controller.resource_show_by_slug_params).to eq(slug: "foo", q: { with_sites: "true" })
    end

    it "omits q rather than raising when it's absent (dry-transformer itself doesn't accept nil)" do
      controller = controller_class.new(params: { id: "1", slug: "foo" })

      expect(controller.resource_show_params).to eq(id: 1)
      expect(controller.resource_show_by_slug_params).to eq(slug: "foo")
    end
  end
end
