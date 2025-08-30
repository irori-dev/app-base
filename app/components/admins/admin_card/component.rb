class Admins::AdminCard::Component < ViewComponent::Base

  include Turbo::FramesHelper

  with_collection_parameter :admin

  def initialize(admin:, current_admin:)
    @admin = admin
    @current_admin = current_admin
  end

  def current_admin?
    @admin == @current_admin
  end

  def editable?
    !current_admin?
  end

end
