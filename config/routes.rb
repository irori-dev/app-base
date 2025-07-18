Rails.application.routes.draw do
  # Health check endpoint
  get "up" => "rails/health#show", as: :rails_health_check
  
  namespace :admins do
    resource :session, only: %i[new create destroy]
    resources :users, only: %i[index show] do
      collection do
        post :insert
      end
    end
    resources :contacts, only: %i[index]
    resources :password_resets, only: %i[new create edit update], param: :token do
      get :sent, on: :collection
    end
    resources :admins, only: %i[index new create edit update destroy]
    
    # エラーテスト用エンドポイント（アラート通知のテスト用）
    get "errors/trigger", to: "errors#trigger"
  end

  namespace :users do
    resource :session, only: %i[new create destroy]
    resources :password_resets, only: %i[new create edit update], param: :token
    resources :email_changes, only: %i[new create], param: :token do
      get :change, on: :member
    end
  end

  resources :users, only: %i[new create] do
    collection do
      get :mypage
    end
  end
  resources :contacts, only: %i[new create]
  root to: "static_pages#home"

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  mount MissionControl::Jobs::Engine, at: "/admins/jobs"
  mount ActionCable.server => "/cable"
end
