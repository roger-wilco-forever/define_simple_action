# frozen_string_literal: true

module DefineSimpleAction
  module BaseServices
    # Rails-подобные before_execute/after_execute callback-цепочки вокруг #execute.
    #
    # Полноценные цепочки: несколько callback'ов на одну точку, с условиями (:if/:unless)
    # и остановкой цепочки. Раз gem построен на dry-monads, остановка — это Failure, а не
    # Rails-овский throw(:abort): если before_execute-callback возвращает Failure, она
    # становится результатом #call, #execute и остальные before_execute/after_execute не
    # вызываются.
    #
    # Callback можно задать именем метода хоста (символ, может быть несколько) или
    # блоком (instance_exec'ится на сервисе). Цепочки наследуются: подкласс добавляет
    # свои callback'и, не трогая callback'и родителя (см. .dup при первом обращении).
    module Callbacks
      def self.included(base)
        base.extend(ClassMethods)
      end

      # *args — service_params для before_execute (см. #run_before_execute_callbacks) и
      # финальный Result для after_execute (см. #run_after_execute_callbacks); guard
      # получает те же args.
      Entry = Struct.new(:callable, :if_guard, :unless_guard, keyword_init: true) do
        def skip?(instance, *args)
          (if_guard && !invoke(if_guard, instance, *args)) || (unless_guard && invoke(unless_guard, instance, *args))
        end

        def call(instance, *args)
          callable.is_a?(Symbol) ? instance.send(callable, *args) : instance.instance_exec(*args, &callable)
        end

        private

        def invoke(guard, instance, *args)
          guard.is_a?(Symbol) ? instance.send(guard, *args) : instance.instance_exec(*args, &guard)
        end
      end

      module ClassMethods
        # if:/unless: приняты через **guards (а не именованными kwargs if:/unless:),
        # т.к. `if`/`unless` — зарезервированные слова и их нельзя прочитать обратно
        # как обычные локальные переменные внутри метода.
        def before_execute(*names, **guards, &block)
          register_callback(before_execute_callbacks, names, guards, block)
        end

        def after_execute(*names, **guards, &block)
          register_callback(after_execute_callbacks, names, guards, block)
        end

        def before_execute_callbacks
          @before_execute_callbacks ||= inherited_callbacks(:before_execute_callbacks)
        end

        def after_execute_callbacks
          @after_execute_callbacks ||= inherited_callbacks(:after_execute_callbacks)
        end

        private

        def inherited_callbacks(reader)
          superclass.respond_to?(reader) ? superclass.public_send(reader).dup : []
        end

        def register_callback(callbacks, names, guards, block)
          callables = names.empty? ? [block] : names
          if_guard = guards[:if]
          unless_guard = guards[:unless]

          callables.each { |callable| callbacks << Entry.new(callable:, if_guard:, unless_guard:) }
        end
      end

      private

      # Всегда возвращает монаду — Failure, если цепочка остановлена, иначе Success().
      # Вызывающий (BaseService#call) забирает её через do-нотацию (yield), как и
      # #validate_params: Failure тут же становится результатом #call, #execute и
      # остальные before_execute/after_execute не вызываются. service_params передаётся
      # колбэку аргументом (и guard'у — тем же аргументом), а не через скрытое состояние.
      def run_before_execute_callbacks(service_params)
        self.class.before_execute_callbacks.each do |entry|
          next if entry.skip?(self, service_params)

          outcome = entry.call(self, service_params)
          return outcome if outcome.is_a?(Dry::Monads::Result) && outcome.failure?
        end

        Success()
      end

      # Всегда запускается после #execute (успех или неудача) — чисто побочный эффект;
      # финальный Result передаётся колбэку аргументом (и guard'у — тем же аргументом),
      # а не через скрытое состояние сервиса.
      def run_after_execute_callbacks(result)
        self.class.after_execute_callbacks.each do |entry|
          next if entry.skip?(self, result)

          entry.call(self, result)
        end
      end
    end
  end
end
