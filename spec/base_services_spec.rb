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

  # Контракт-двойник: всегда падает, .errors.to_h возвращает замороженный Hash — как
  # реальный dry-validation MessageSet#to_h (см. deep_dup-тест ниже).
  let(:failing_contract_class) do
    Class.new do
      def call(_params)
        FailureResult.new
      end

      class FailureResult
        include Dry::Monads[:result]

        def to_monad
          Failure(ErrorSet.new)
        end
      end

      class ErrorSet
        def errors
          self
        end

        def to_h
          { ids: ["Должен быть массивом"] }.freeze
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

    it "tags a contract validation Failure with type: :contract_validation and deep_dup's the " \
       "errors — the host matches on :type to pick a response format, and must not hit " \
       "FrozenError mutating dry-validation's frozen MessageSet#to_h in place" do
      contract = failing_contract_class
      klass = Class.new(service_class) { define_method(:contract) { contract } }

      result = klass.new(model: "Widget").call({})

      expect(result).to be_failure
      expect(result.failure).to eq(type: :contract_validation, errors: { ids: ["Должен быть массивом"] })
      expect(result.failure[:errors]).not_to be_frozen
      expect { result.failure[:errors].delete(:ids) }.not_to raise_error
    end

    it "has no notify/notify_data of its own — that's a host concern (see README, 'Notify — не в gem'е')" do
      expect(described_class.private_method_defined?(:notify_data)).to eq(false)

      # dry-initializer молча игнорирует непойманный kwarg, если он не объявлен через
      # option — notify_data просто никуда не попадает и ничего не запускает.
      result = service_class.new(model: "Widget", notify_data: { watch_keys: [:title] }).call({})

      expect(result).to be_success
    end

    it "lets a host rebuild notify entirely on public extension points (option/after_execute/call_hook)" do
      calls = []
      notifiable = Module.new do
        def self.included(base)
          base.option :notify_data, optional: true, reader: :private
          base.after_execute :dispatch_notify, if: :notify_applicable?
        end

        private

        def notify_applicable?(result)
          result.success? && notify_data&.dig(:watch_keys)&.any?
        end

        def dispatch_notify(result)
          call_hook(:notify, result.value!)
        end
      end

      klass = Class.new(service_class) do
        include notifiable
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
      expect(service.send(:call_hook, :index_response_class)).to be_nil
      expect(service.class.private_method_defined?(:soft_delete?)).to eq(false)
      expect(service.class.private_method_defined?(:index_response_class)).to eq(false)
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

    describe "before_execute/after_execute callback chains" do
      it "runs multiple before_execute/after_execute callbacks (methods and blocks) in registration order" do
        trace = []
        received_params = nil
        klass = Class.new(service_class) do
          before_execute :first_before
          before_execute { trace << :second_before }
          after_execute :first_after
          after_execute { trace << :second_after }

          define_method(:first_before) { |params| received_params = params; trace << :first_before }
          define_method(:first_after) { |_result| trace << :first_after }
        end

        klass.new(model: "Widget").call(title: "Foo")

        expect(trace).to eq(%i[first_before second_before first_after second_after])
        expect(received_params).to eq(title: "Foo")
      end

      it "halts the chain when a before_execute callback returns Failure — #execute and after_execute never run" do
        executed = false
        after_ran = false
        klass = Class.new(service_class) do
          before_execute :blocker

          define_method(:blocker) { |_params| Failure(:blocked) }
          define_method(:execute) { |**_params| executed = true; Success(:unreachable) }
          define_method(:after_execute_probe) { |_result| after_ran = true }

          after_execute :after_execute_probe
        end

        result = klass.new(model: "Widget").call({})

        expect(result).to be_failure
        expect(result.failure).to eq(:blocked)
        expect(executed).to eq(false)
        expect(after_ran).to eq(false)
      end

      it "skips a callback whose :if guard is falsy and runs one whose :unless guard is falsy" do
        trace = []
        klass = Class.new(service_class) do
          before_execute :skipped, if: :never?
          before_execute :included, unless: :never?

          define_method(:never?) { |_params| false }
          define_method(:skipped) { |_params| trace << :skipped }
          define_method(:included) { |_params| trace << :included }
        end

        klass.new(model: "Widget").call({})

        expect(trace).to eq([:included])
      end

      it "inherits parent callbacks without letting a subclass mutate the parent's chain" do
        parent = Class.new(service_class) do
          before_execute :parent_cb
          define_method(:parent_cb) { |_params| (self.trace ||= []) << :parent_cb }
          attr_accessor :trace
        end
        child = Class.new(parent) do
          before_execute :child_cb
          define_method(:child_cb) { |_params| (self.trace ||= []) << :child_cb }
        end

        child.new(model: "Widget").call({})

        expect(parent.before_execute_callbacks.size).to eq(1)
        expect(child.before_execute_callbacks.size).to eq(2)
      end
    end

    describe "dry-monitor instrumentation" do
      after { DefineSimpleAction.instance_variable_set(:@notifications, nil) }

      it "publishes define_simple_action.execute with service/model/success/time around #execute" do
        events = []
        DefineSimpleAction.notifications.subscribe("define_simple_action.execute") { |event| events << event.payload }

        service_class.new(model: "Widget").call({})

        expect(events.size).to eq(1)
        expect(events.first).to include(model: "Widget", success: true)
        expect(events.first[:time]).to be_a(Integer)
      end

      it "still reports success: false when #execute returns a Failure" do
        events = []
        DefineSimpleAction.notifications.subscribe("define_simple_action.execute") { |event| events << event.payload }

        klass = Class.new(service_class) { define_method(:execute) { |**_params| Failure(:nope) } }
        klass.new(model: "Widget").call({})

        expect(events.first).to include(success: false)
      end
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

    it "has no after_mutation call_hook of its own — a host rebuilds it via after_execute " \
       "(see README, 'after_mutation — не в gem'е')" do
      mutated = []
      klass = Class.new(service_class) do
        after_execute :track_mutation, if: ->(result) { result.success? }

        define_method(:track_mutation) { |_result| mutated << model.name }
      end

      klass.new(model: record_class).call(title: "Foo")

      expect(mutated).to eq(["Widget"])
    end

    it "tags a save failure with type: :invalid_record instead of running a call_hook" do
      failing_record_class = Class.new(record_class) do
        def save
          @saved = false
          @errors_messages = { title: ["can't be blank"] }
          @saved
        end
      end
      klass = Class.new(service_class) { define_method(:scope) { failing_record_class } }

      result = klass.new(model: record_class).call(title: "Foo")

      expect(result).to be_failure
      expect(result.failure).to eq(type: :invalid_record, errors: { title: ["can't be blank"] })
    end

    it "does not rescue exceptions raised from #create_resource — that's a host concern (see README, " \
       "'ActiveRecord/ransack/discard как монкипатч хоста')" do
      raising_class = Class.new(record_class) do
        def initialize(*)
          super
          raise "boom"
        end
      end
      klass = Class.new(service_class) { define_method(:scope) { raising_class } }

      expect { klass.new(model: record_class).call(title: "Foo") }.to raise_error("boom")
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

    it "returns Success — a host rebuilds after_mutation via after_execute (see README, " \
       "'after_mutation — не в gem'е')" do
      mutated = []
      klass = Class.new(service_class) do
        after_execute :track_mutation, if: ->(result) { result.success? }

        define_method(:track_mutation) { |_result| mutated << model.name }
      end

      result = klass.new(model: fake_model_class).call(id: 1, title: "Foo")

      expect(result).to be_success
      expect(mutated).to eq(["Widget"])
    end

    it "tags an update failure with type: :invalid_record instead of running a call_hook" do
      contract = passing_contract_class
      failing_record = record_class.new
      failing_record.saved = false
      failing_record.errors_messages = { title: ["can't be blank"] }
      fake_model = fake_model_class
      fake_model.define_singleton_method(:find) { |_id| failing_record }

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:model) { fake_model }
      end

      result = klass.new(model: fake_model_class).call(id: 1, title: "Foo")

      expect(result).to be_failure
      expect(result.failure).to eq(type: :invalid_record, errors: { title: ["can't be blank"] })
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

    it "tags a destroy failure with type: :invalid_record instead of running a call_hook" do
      contract = passing_contract_class
      failing_record = record_class.new
      def failing_record.destroy
        @errors_messages = { base: ["can't be destroyed"] }
        false
      end

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:destroy_resource) { |_params| failing_record }
      end

      result = klass.new(model: record_class).call(id: 1)

      expect(result).to be_failure
      expect(result.failure).to eq(type: :invalid_record, errors: { base: ["can't be destroyed"] })
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

    it "returns all destroyed records on success — a host rebuilds after_mutation via " \
       "after_execute (see README, 'after_mutation — не в gem'е')" do
      records = [record_class.new, record_class.new]
      relation = relation_class.new(records)
      contract = passing_contract_class
      mutated = []

      klass = Class.new(described_class) do
        after_execute :track_mutation, if: ->(result) { result.success? }

        define_method(:contract) { contract }
        define_method(:track_mutation) { |_result| mutated << model.name }
        define_method(:resource_to_delete) { |_ids| relation }
      end

      result = klass.new(model: record_class).call(ids: [1, 2])

      expect(result).to be_success
      expect(result.value!).to all(satisfy(&:destroyed?))
      expect(mutated).to eq(["Widget"])
    end

    it "tags a partial failure with type: :batch_destroy instead of running a call_hook" do
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
      expect(result.failure).to eq(type: :batch_destroy, errors: ["can't be destroyed"])
    end
  end

  describe DefineSimpleAction::BaseServices::IndexService do
    # Двойник query-объекта (например, ActiveRecord::Relation), чтобы не тянуть БД
    # в тесты gem'а. Без #ransack — дефолтный #prepare_query его больше не вызывает.
    let(:relation_class) do
      Class.new do
        def initialize(items)
          @items = items
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

    it "#prepare_query defaults to plain #scope(params) — no Ransack call, that's a host concern" do
      relation = relation_class.new(%w[a b])
      contract = passing_contract_class

      klass = Class.new(described_class) do
        define_method(:contract) { contract }
        define_method(:scope) { |_params| relation }
      end
      service = klass.new(model: record_class)

      expect(service.send(:prepare_query, q: { title_cont: "x" })).to equal(relation)
    end

    describe "#cast_boolean (dry-transformer, no ActiveModel)" do
      let(:service) { klass.new(model: record_class) }
      let(:klass) do
        contract = passing_contract_class
        Class.new(described_class) { define_method(:contract) { contract } }
      end

      it "recognizes common truthy/falsy param values" do
        expect(service.send(:cast_boolean, "true")).to eq(true)
        expect(service.send(:cast_boolean, "1")).to eq(true)
        expect(service.send(:cast_boolean, true)).to eq(true)
        expect(service.send(:cast_boolean, "false")).to eq(false)
        expect(service.send(:cast_boolean, "0")).to eq(false)
        expect(service.send(:cast_boolean, false)).to eq(false)
      end

      it "treats nil and unrecognized values as false rather than raising" do
        expect(service.send(:cast_boolean, nil)).to eq(false)
        expect(service.send(:cast_boolean, "garbage")).to eq(false)
      end
    end
  end
end
