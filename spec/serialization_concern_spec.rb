# frozen_string_literal: true

RSpec.describe DefineSimpleAction::SerializationConcern do
  # Двойник dry-monads Result — не тянем dry-monads в тесты Concern-слоя (см.
  # define_simple_action_spec.rb, тот же подход для DefineSimpleAction::Concern).
  let(:result_class) do
    Struct.new(:ok, :payload) do
      def failure?
        !ok
      end

      def value!
        payload
      end

      def failure
        payload
      end
    end
  end

  let(:controller_class) do
    Class.new do
      include DefineSimpleAction::Concern
      include DefineSimpleAction::SerializationConcern

      def prefix
        "Widgets"
      end
    end
  end

  let(:controller) { controller_class.new }

  let(:serializer_class) do
    Class.new do
      def self.call(object, options)
        { rendered: object, options: }
      end
    end
  end

  describe "#serialize_for_action — success" do
    before { stub_const("Widgets::ShowSerializer", serializer_class) }

    it "resolves the serializer by `\#{prefix}::\#{name.camelize}Serializer` and encodes exactly what it returns — no {data:} wrapping of its own" do
      result = result_class.new(true, "a widget")

      json = controller.serialize_for_action("show", result, {})

      expect(JSON.parse(json, symbolize_names: true)).to eq(rendered: "a widget", options: {})
    end

    it "lets `set_serializer_name_for_\#{name}` pick a different class" do
      stub_const("Widgets::CustomSerializer", serializer_class)
      def controller.set_serializer_name_for_show
        "Widgets::CustomSerializer"
      end

      result = result_class.new(true, "a widget")
      json = controller.serialize_for_action("show", result, {})

      expect(JSON.parse(json, symbolize_names: true)).to eq(rendered: "a widget", options: {})
    end

    it "passes #serializer_options through to #render_resource" do
      def controller.serializer_options(_name, service_params)
        { q: service_params[:q] }
      end

      result = result_class.new(true, "a widget")
      json = controller.serialize_for_action("show", result, { q: { title_cont: "foo" } })

      expect(JSON.parse(json, symbolize_names: true)).to eq(
        rendered: "a widget", options: { q: { title_cont: "foo" } }
      )
    end
  end

  describe "#serialize_for_action — response shape is entirely the serializer's job, gem doesn't special-case it" do
    let(:index_response_class) { Struct.new(:data, :meta) }

    it "for ACTION_INDEX, passes the whole IndexResponse (data:/meta:) to the resolved serializer as-is" do
      index_serializer = Class.new do
        def self.call(index_response, _options)
          { data: index_response.data, meta: index_response.meta }
        end
      end
      stub_const("Widgets::IndexSerializer", index_serializer)
      response = index_response_class.new(%w[a b], { count: 2, limit: 10, offset: 0 })
      result = result_class.new(true, response)

      json = controller.serialize_for_action(::DefineSimpleAction::Concern::ACTION_INDEX, result, {})

      expect(JSON.parse(json, symbolize_names: true)).to eq(
        data: %w[a b],
        meta: { count: 2, limit: 10, offset: 0 }
      )
    end

    it "for ACTION_BATCH_DESTROY, resolves a serializer by convention too — an ids-only response is the host's choice, not the gem's" do
      batch_destroy_serializer = Class.new do
        def self.call(records, _options)
          { data: records.map(&:id) }
        end
      end
      stub_const("Widgets::BatchDestroySerializer", batch_destroy_serializer)
      records = [Struct.new(:id).new(1), Struct.new(:id).new(2)]
      result = result_class.new(true, records)

      json = controller.serialize_for_action(::DefineSimpleAction::Concern::ACTION_BATCH_DESTROY, result, {})

      expect(JSON.parse(json, symbolize_names: true)).to eq(data: [1, 2])
    end
  end

  describe "#serialize_for_action — DefineSimpleAction::Concern::ACTION_DESTROY" do
    it "returns nil without resolving a serializer class (no NameError even if none is defined)" do
      result = result_class.new(true, :whatever)

      expect(controller.serialize_for_action(::DefineSimpleAction::Concern::ACTION_DESTROY, result, {})).to be_nil
    end
  end

  describe "#serialize_for_action — failure" do
    it "raises NotImplementedError for #render_error by default — gem has no opinion on the error envelope" do
      result = result_class.new(false, { type: :invalid_record, errors: { name: ["can't be blank"] } })

      expect { controller.serialize_for_action("create", result, {}) }.to raise_error(NotImplementedError)
    end

    it "encodes whatever #render_error returns once the host defines it" do
      def controller.render_error(failure, _options)
        { error: failure[:type] }
      end

      result = result_class.new(false, { type: :invalid_record, errors: {} })
      json = controller.serialize_for_action("create", result, {})

      expect(JSON.parse(json, symbolize_names: true)).to eq(error: "invalid_record")
    end
  end

  describe "`fetch_serializer_for_\#{name}` — full escape hatch" do
    it "bypasses serializer resolution, error handling and rendering entirely" do
      def controller.fetch_serializer_for_index(result, _service_params)
        "custom #{result.value!}"
      end

      result = result_class.new(true, "widget")

      expect(controller.serialize_for_action("index", result, {})).to eq("custom widget")
    end
  end

  describe "#render_resource — the one place that knows about a concrete serialization library" do
    it "can be overridden wholesale to swap the library (e.g. Blueprinter's #render_as_json)" do
      blueprinter_like_class = Class.new do
        def self.render_as_json(object, options)
          { blueprinter: object, options: }
        end
      end
      stub_const("Widgets::ShowSerializer", blueprinter_like_class)

      def controller.render_resource(serializer_class, object, options)
        serializer_class.render_as_json(object, options)
      end

      result = result_class.new(true, "a widget")
      json = controller.serialize_for_action("show", result, {})

      expect(JSON.parse(json, symbolize_names: true)).to eq(blueprinter: "a widget", options: {})
    end
  end
end
