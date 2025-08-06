class ApplicationController < ActionController::Base

  include Authenticatable

  before_action :prepare_exception_notifier
  before_action :set_logging_context

  # Authenticatable concern methods
  alias require_user! require_resource!
  alias current_user current_resource
  alias user_signed_in? resource_signed_in?

  helper_method :current_user, :user_signed_in?

  private

  def prepare_exception_notifier
    request.env['exception_notifier.exception_data'] = {
      current_user:,
      app: 'AppBase',
    }
  end

  def require_not_user!
    return unless user_signed_in?

    flash[:alert] = '既にログインしています'
    redirect_to root_path
  end

  def resource_class
    User::Core
  end

  def session_key
    :user_id
  end

  def sign_in_path
    new_users_session_path
  end

  def after_sign_in_path
    root_path
  end

  def set_logging_context
    # Set user context for logging
    Thread.current[:current_user_id] = current_user&.id
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
