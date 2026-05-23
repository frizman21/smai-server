require "sidekiq/web"
require "sidekiq/cron/web" # registers the Cron tab in the Sidekiq UI

Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }

  # Browseable inbox of every email captured by ActionMailer in
  # development. Mounted only in development so production can never
  # serve this route.
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Sidekiq's built-in web UI. Gated behind Devise sign-in + admin flag —
  # the constraint short-circuits with a 404 (not a redirect to sign in)
  # for unauthorized users so the path doesn't advertise itself.
  authenticate :user, ->(u) { u.is_admin } do
    mount Sidekiq::Web => "/sidekiq"
  end
  resources :invitations, only: [:show, :create, :destroy]
  resources :users, only: [:index, :edit, :update]
  get "profile" => "profiles#show", as: :profile
  get "profile/edit" => "profiles#edit", as: :edit_profile
  patch "profile" => "profiles#update"
  get "change_password" => "passwords#edit", as: :change_password
  patch "change_password" => "passwords#update"
  resource :analytics, only: [:show], controller: "analytics"

  get "/auth/:provider/callback", to: "email_delegations#create", as: :email_delegation_callback
  get "/auth/failure", to: "email_delegations#failure", as: :email_delegation_failure
  resources :email_delegations, only: [:destroy]
  resources :job_proposals, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    collection do
      get :poll
    end
    member do
      patch :resume
      patch :pause
      post  :launch_campaign
      patch :mark_won
      patch :mark_lost
      patch :revert_pipeline_stage
      patch :revert_to_edit
      patch :approve
      patch :restore
    end
    resources :step_instances, only: [:show], controller: "campaign_step_instances" do
      member do
        post :check_thread
        post :simulate_reply
      end
    end
    resources :campaign_instances, only: [:show]
    resources :histories, only: [:show], controller: "job_proposal_histories"
  end

  namespace :admin do
    resource :analytics, only: [:show], controller: "analytics"
    resources :chats, only: [:index, :show]
    resources :messages, only: [:index]
    resources :tool_calls, only: [:index]
    resources :models, only: [:index]
    resources :pdf_processing_revisions, only: [:index, :show, :new, :create]
    resource :application_mailbox, only: [:show, :destroy], controller: "application_mailbox"
    resources :integrations, only: [:index] do
      collection { post :check }
    end
    resources :tenants, only: [:index, :show, :new, :create, :edit, :update] do
      resources :invitations, only: [:create, :destroy]
      resources :locations, only: [:new, :create]
      resources :users, only: [:show, :edit, :update]
      resource :activations, only: [:show], controller: "activations"
      resources :job_type_activations, only: [:create, :destroy] do
        member { post :activate_all_scenarios }
      end
      resources :scenario_activations, only: [:create, :destroy]
    end
    resources :users, only: [:index]
    resources :job_types do
      resources :scenarios, only: [:new, :create]
    end
    resources :scenarios, only: [:show, :edit, :update, :destroy]
    resources :job_proposals, only: [:new, :create]
    resource :trash, only: [:show], controller: "trash"
    resources :campaigns do
      member do
        patch :approve
        patch :pause
        patch :resume
        patch :restore
      end
      resources :revisions, only: [:show, :create], controller: "campaign_revisions" do
        member do
          patch :approve
        end
        resources :steps, only: [:new, :create, :edit, :update, :destroy], controller: "campaign_steps" do
          collection do
            patch :reorder
          end
        end
      end
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
end
