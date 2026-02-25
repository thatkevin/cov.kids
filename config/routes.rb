Rails.application.routes.draw do
  devise_for :users

  namespace :admin do
    resources :events, only: [ :index, :edit, :update ] do
      member do
        patch :approve
        patch :reject
      end
    end
    resources :feeds do
      member { post :trigger }
    end
    resources :sources, only: [ :index, :new, :create, :edit, :update, :destroy ]
    root to: "events#index"
  end

  root "site#index"
  get "weeks",        to: "site#weeks_index", as: :weeks_index
  get "weeks/:week_id", to: "site#week",      as: :week_page,
      constraints: { week_id: /\d{4}-W\d{1,2}/ }
  get ":year",          to: "site#year",      constraints: { year: /\d{4}/ }
  get ":year/:month",   to: "site#month",     constraints: { year: /\d{4}/, month: /\d{2}/ }
  get ":year/:month/:day", to: "site#day",    constraints: { year: /\d{4}/, month: /\d{2}/, day: /\d{2}/ }

  get "up" => "rails/health#show", as: :rails_health_check
end
