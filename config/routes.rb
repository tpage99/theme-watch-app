Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#landing"

  get "dashboard", to: "dashboard#index", as: :dashboard
  get "my-apps",   to: "my_apps#index",   as: :my_apps
  get "my-apps/:slug/compatibilities",
      to: "my_app_compatibilities#index",
      as: :my_app_compatibilities,
      constraints: { slug: /[a-z0-9][a-z0-9\-]*/ }
  post "my-apps/:slug/compatibilities",
       to: "my_app_compatibilities#create",
       constraints: { slug: /[a-z0-9][a-z0-9\-]*/ }
  patch "my-apps/:slug/compatibilities/:theme_title",
        to: "my_app_compatibilities#update",
        as: :my_app_compatibility,
        constraints: { slug: /[a-z0-9][a-z0-9\-]*/, theme_title: %r{[^/]+} }
  get "alerts",    to: "alerts#index",    as: :alerts
  get "settings",  to: "settings#index",  as: :settings

  get  "sign-in",  to: "sessions#new",      as: :sign_in
  get  "sign-up",  to: "sessions#sign_up",  as: :sign_up
  delete "sign-out", to: "sessions#destroy", as: :sign_out
end
