require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Myapp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :queue, reading: :queue } }
    config.mission_control.jobs.base_controller_class = "Admins::BaseController"

    config.time_zone = "Tokyo"

    config.i18n.default_locale = :ja
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}").to_s]

    config.autoload_paths += %W[#{config.root}/lib]
    config.allow_origins = Rails.application.credentials.dig(:allow_origins) || []

    config.silence_healthcheck_path = "/up"

    config.action_controller.default_url_options = if Rails.env == "development" || Rails.env == "test"
      { host: ENV["HOST"], port: ENV["PORT"] }
    else
      { host: Rails.application.credentials.dig(:base, :host), protocol: "https" }
    end
  end
end

Rails.application.reloader.to_prepare do
  ActiveStorage::Blob
end
