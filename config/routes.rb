Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do  
    namespace :v2 do
      namespace :storefront do
        resources :eurobank_payments, only: [:create] do
          collection do
            post 'failure'
            post 'success'
          end
        end
      end
    end
  end
end