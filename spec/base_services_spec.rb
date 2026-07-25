# frozen_string_literal: true

RSpec.describe "DefineSimpleAction::BaseServices" do
  # Модель-двойник: минимальный ActiveRecord-подобный интерфейс, без реальной БД.
  let(:record_class) do
    Class.new do
      attr_accessor :id, :saved, :errors_messages, :destroyed_flag, :discarded_flag

      def self.name
        "Widget"
      end

      def initialize(attrs = {})
        @attrs = attrs
        @saved = true
        @errors_messages = {}
      end

      def save
        @saved
      end

      def update(_attrs)
        @saved
      end

      def destroy
        @destroyed_flag = true
      end

      def discard
        @discarded_flag = true
      end

      def destroyed?
        !!@destroyed_flag
      end

      def discarded?
        !!@discarded_flag
      end

      def errors
        Struct.new(:messages, :full_messages).new(@errors_messages, @errors_messages.values.flatten)
      end
    end
  end

  # Контракт-двойник: всегда успешен, возвращает params как есть (без реального dry-validation).
  let(:passing_contract_class) do
    Class.new do
      def call(params)
        SuccessResult.new(params)
      end

      class SuccessResult
        include Dry::Monads[:result]

        def initialize(params)
          @params = params
        end

        def to_monad
          Success(@params)
        end
      end
    end
  end

  describe DefineSimpleAction::BaseServices::BaseService do
    let(:service_class) do
      contract = passing_contract_class

      Class.new(described_class) do
        define_method(:contract) { contract }

        def execute(**_params)
          Success(:executed)
        end
      end
    end

    it "validates via the injected contract and returns Success from #execute" do
      service = service_class.new(model: "Widget")

      expect(service.call({})).to be_success
    end

    it "calls #notify only when notify_data has watch_keys" do
      calls = []
      klass = Class.new(service_class) do
        define_method(:notify) { |result| calls << result }
      end

      klass.new(model: "Widget", notify_data: { watch_keys: [:title] }).call({})
      expect(calls).to eq([:executed])

      calls.clear
      klass.new(model: "Widget", notify_data: { watch_keys: [] }).call({})
      expect(calls).to be_empty

      klass.new(model: "Widget").call({})
      expect(calls).to be_empty
    end

    it "#call_hook returns nil for a hook the host never defined (no stub declared in the gem)" do
      service = service_class.new(model: "Widget")

      expect(service.send(:call_hook, :soft_delete?, record_class)).to be_nil
      expect(service.send(:call_hook, :after_mutation, "Widget")).to be_nil
      expect(service.class.private_method_defined?(:soft_delete?)).to eq(false)
      expect(service.class.private_method_defined?(:after_mutation)).to eq(false)
    end

    it "#call_hook dispatches to whatever method the host defines under that name" do
      klass = Class.new(service_class) do
        define_method(:soft_delete?) { |_model_class| true }
      end

      expect(klass.new(model: "Widget").send(:call_hook, :soft_delete?, record_class)).to eq(true)
    end

    it "raises when no validation contract can be resolved by naming convention" do
      klass = Class.new(described_class) do
        def execute(**_params)
          Success(:ok)
        end
      end

      expect { klass.new(model: "Widget").call({}) }.to raise_error(NotImplementedError, /Validation contract/)
    end
  end

  describe DefineSimpleAction::BaseServices::CreateService do
    let(:service_class) do
      klass = record_class
      contract = passing_contract_class

      Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:scope) { klass }
      end
    end

    it "returns Success with the created resource" do
      service = service_class.new(model: record_class)

      result = service.call(title: "Foo")

      expect(result).to be_success
      expect(result.value!).to be_a(record_class)
    end

    it "calls after_mutation with the model name on success" do
      mutated = []
      klass = Class.new(service_class) do
        define_method(:after_mutation) { |name| mutated << name }
      end

      klass.new(model: record_class).call(title: "Foo")

      expect(mutated).to eq(["Widget"])
    end

    it "returns Failure via #invalid_record_error when save fails" do
      failing_record_class = Class.new(record_class) do
        def save
          @saved = false
        end
      end
      klass = Class.new(service_class) { define_method(:scope) { failing_record_class } }

      result = klass.new(model: record_class).call(title: "Foo")

      expect(result).to be_failure
    end

    it "wraps ActiveRecord::InvalidForeignKey via #foreign_key_error" do
      raising_class = Class.new(record_class) do
        def initialize(*)
          super
          raise ActiveRecord::InvalidForeignKey, "boom"
        end
      end
      klass = Class.new(service_class) { define_method(:scope) { raising_class } }

      result = klass.new(model: record_class).call(title: "Foo")

      expect(result).to be_failure
      expect(result.failure).to eq(error: "boom")
    end
  end

  describe DefineSimpleAction::BaseServices::UpdateService do
    let(:fake_model_class) do
      Class.new do
        def self.name
          "Widget"
        end
      end
    end

    let(:service_class) do
      contract = passing_contract_class
      record = record_class.new
      fake_model = fake_model_class
      fake_model.define_singleton_method(:find) { |_id| record }

      Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:model) { fake_model }
      end
    end

    it "returns Success and calls after_mutation when update succeeds" do
      mutated = []
      klass = Class.new(service_class) do
        define_method(:after_mutation) { |name| mutated << name }
      end

      result = klass.new(model: fake_model_class).call(id: 1, title: "Foo")

      expect(result).to be_success
      expect(mutated).to eq(["Widget"])
    end

    it "returns Failure via #invalid_record_error when update fails" do
      contract = passing_contract_class
      failing_record = record_class.new
      failing_record.saved = false
      fake_model = fake_model_class
      fake_model.define_singleton_method(:find) { |_id| failing_record }

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:model) { fake_model }
      end

      result = klass.new(model: fake_model_class).call(id: 1, title: "Foo")

      expect(result).to be_failure
    end
  end

  describe DefineSimpleAction::BaseServices::DestroyService do
    let(:service_class) do
      contract = passing_contract_class
      record = record_class.new

      Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:destroy_resource) { |_params| record }
      end
    end

    it "hard-destroys by default (soft_delete? false)" do
      service = service_class.new(model: record_class)

      result = service.call(id: 1)

      expect(result).to be_success
      expect(result.value!.destroyed?).to eq(true)
      expect(result.value!.discarded?).to eq(false)
    end

    it "discards when soft_delete? is overridden to true" do
      klass = Class.new(service_class) { define_method(:soft_delete?) { |_model| true } }

      result = klass.new(model: record_class).call(id: 1)

      expect(result).to be_success
      expect(result.value!.discarded?).to eq(true)
      expect(result.value!.destroyed?).to eq(false)
    end
  end

  describe DefineSimpleAction::BaseServices::BatchDestroyService do
    let(:relation_class) do
      Class.new do
        def initialize(records)
          @records = records
        end

        def destroy_all
          @records.each(&:destroy)
          @records
        end

        def discard_all
          @records.each(&:discard)
          @records
        end
      end
    end

    it "reports after_mutation and returns all destroyed records on success" do
      records = [record_class.new, record_class.new]
      relation = relation_class.new(records)
      contract = passing_contract_class
      mutated = []

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:after_mutation) { |name| mutated << name }
        define_method(:resource_to_delete) { |_ids| relation }
      end

      result = klass.new(model: record_class).call(ids: [1, 2])

      expect(result).to be_success
      expect(result.value!).to all(satisfy(&:destroyed?))
      expect(mutated).to eq(["Widget"])
    end

    it "returns Failure via #batch_destroy_error when some records are not destroyed" do
      stuck_record = record_class.new
      def stuck_record.destroy
        # не помечаем как destroyed — имитируем частичный отказ
      end
      stuck_record.errors_messages = { base: ["can't be destroyed"] }
      records = [record_class.new, stuck_record]
      relation = relation_class.new(records)
      contract = passing_contract_class

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:resource_to_delete) { |_ids| relation }
      end

      result = klass.new(model: record_class).call(ids: [1, 2])

      expect(result).to be_failure
      expect(result.failure).to eq(errors: ["can't be destroyed"])
    end
  end

  describe DefineSimpleAction::BaseServices::IndexService do
    # Двойник ActiveRecord::Relation, чтобы не тянуть Ransack/БД в тесты gem'а.
    let(:relation_class) do
      Class.new do
        def initialize(items)
          @items = items
        end

        def ransack(_q, auth_object:)
          self
        end

        def result
          self
        end

        def limit(n)
          @limit = n
          self
        end

        def offset(n)
          sliced = @items.drop(n || 0)
          @limit ? sliced.first(@limit) : sliced
        end

        def size
          @items.size
        end
      end
    end

    it "builds an IndexResponse with paginated data and meta" do
      items = %w[a b c d e]
      relation = relation_class.new(items)
      contract = passing_contract_class

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:scope) { |_params| relation }
      end

      result = klass.new(model: record_class).call(limit: 2, offset: 0, q: {})

      expect(result).to be_success
      response = result.value!
      expect(response.data).to eq(%w[a b])
      expect(response.meta.count).to eq(5)
      expect(response.meta.limit).to eq(2)
      expect(response.meta.offset).to eq(0)
    end

    it "lets a host override #index_response_class to preserve its own type/is_a? checks" do
      custom_response_class = Class.new(DefineSimpleAction::BaseServices::Responses::IndexResponse)
      relation = relation_class.new(%w[a])
      contract = passing_contract_class

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:scope) { |_params| relation }
        define_method(:index_response_class) { custom_response_class }
      end

      result = klass.new(model: record_class).call(limit: 1, offset: 0, q: {})

      expect(result.value!).to be_a(custom_response_class)
    end
  end
end
