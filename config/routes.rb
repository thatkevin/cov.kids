Rails.application.routes.draw do
  devise_for :users

  namespace :admin do
    resources :events, only: [ :index, :edit, :update ] do
      member do
        patch :approve
        patch :reject
        patch :feature
        post  :merge
      end
    end
    resources :feeds do
      member { post :trigger }
    end
    resources :venues do
      member do
        post :merge
        post :merge_into
      end
    end
    resources :sources, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      collection { post :run_by_type }
      member do
        post :reprocess
        patch :archive
        patch :unarchive
      end
    end
    resource :site, only: [], controller: "site" do
      post :publish
    end
    root to: "events#index"
  end

  root "site#index"
  get "about", to: "site#about"
  get "weeks",        to: "site#weeks_index", as: :weeks_index
  get "weeks/:week_id", to: "site#week",      as: :week_page,
      constraints: { week_id: /\d{4}-W\d{1,2}/ }
  get ":year",          to: "site#year",      constraints: { year: /\d{4}/ }
  get ":year/:month",   to: "site#month",     constraints: { year: /\d{4}/, month: /\d{2}/ }
  get ":year/:month/:day", to: "site#day",    constraints: { year: /\d{4}/, month: /\d{2}/, day: /\d{2}/ }

  get "img", to: "image_proxy#show", as: :image_proxy

  get "up" => "rails/health#show", as: :rails_health_check
end
