class Admins::BaseController < ApplicationController

  include Authenticatable

  before_action :prepare_exception_notifier
  before_action :require_admin!
  before_action :set_admin_logging_context

  layout 'admins'

  # Authenticatable concern methods
  alias require_admin! require_resource!
  alias current_admin current_resource
  alias admin_signed_in? resource_signed_in?

  helper_method :current_admin, :admin_signed_in?

  private

  def resource_class
    Admin
  end

  def session_key
    :admin_id
  end

  def sign_in_path
    Rails.application.routes.url_helpers.new_admins_session_path
  end

  def after_sign_in_path
    Rails.application.routes.url_helpers.admins_root_path
  end

  def prepare_exception_notifier
    request.env['exception_notifier.exception_data'] = {
      current_admin_id: current_admin&.id,
    }
  end

  def set_admin_logging_context
    # Override user context with admin context
    Thread.current[:current_user_id] = "admin_#{current_admin&.id}" if current_admin
    Thread.current[:controller_name] = controller_name
    Thread.current[:action_name] = action_name
    Thread.current[:filtered_params] = filtered_params_for_logging
  end

  def filtered_params_for_logging
    params.to_unsafe_h.except(:controller, :action, :authenticity_token)
  rescue StandardError
    {}
  end

end
