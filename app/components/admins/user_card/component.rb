class Admins::UserCard::Component < ViewComponent::Base

  include Turbo::FramesHelper

  with_collection_parameter :user

  def initialize(user:)
    @user = user
  end

end
