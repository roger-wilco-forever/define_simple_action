# frozen_string_literal: true

require "dry/monitor"

module DefineSimpleAction
  # Общий на весь процесс dry-monitor notifier. Публикует события вокруг
  # BaseService#execute — подписка (метрики/логи/трейсинг) целиком на хосте,
  # gem только публикует и не навязывает, что с событием делать:
  #
  #   DefineSimpleAction.notifications.subscribe("define_simple_action.execute") do |event|
  #     StatsD.timing("services.#{event[:service]}", event[:time])
  #   end
  def self.notifications
    @notifications ||= Dry::Monitor::Notifications.new(:define_simple_action).tap do |notifications|
      notifications.register_event("define_simple_action.execute")
    end
  end
end
