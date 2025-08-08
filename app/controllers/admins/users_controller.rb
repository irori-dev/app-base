class Admins::UsersController < Admins::BaseController

  include Searchable

  def index
    @users = setup_search(User::Core)
      .page(params[:page])
  end

  def show
    @user = User::Core.includes(:password_resets, :email_changes).find(params[:id])
  end

  def insert
    count = params[:count].to_i
    CreateSampleUsersJob.perform_later(count)
    flash.now[:notice] = "#{count}件のユーザーを作成しました"
  end

end
