ActionController::Routing::Routes.draw do |map|
  map.resources :upstream_channels

  #map.resources :licenses

  # The priority is based upon order of creation: first created -> highest priority.
  
  # Sample of regular route:
  # map.connect 'products/:id', :controller => 'catalog', :action => 'view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  # map.purchase 'products/:id/purchase', :controller => 'catalog', :action => 'purchase'
  # This route can be invoked with purchase_url(:id => product.id)

  # You can have the root of your site routed by hooking up '' 
  # -- just remember to delete public/index.html.
  # map.connect '', :controller => "welcome"

  # Allow downloading Web Service WSDL as a file with an extension
  # instead of a file named 'wsdl'
  map.resources :licenses
  map.resources :down_alarms
  map.resources :alarms
  map.resources :down_alarm_summarys
  map.resources :alarm_summarys
  map.resources :locales
  map.resources :passwords
  map.resources :analyzers
  map.connect 'g_reports/snapshot/:sid' , :controller =>'g_reports', :action=> 'snapshot'
  map.connect ':controller/service.wsdl', :action => 'wsdl'
  map.resources :status, :only => [:index]
  map.resources :queries, :only => [:index, :destroy]
  map.resources :report, :only => [:index, :destroy, :create]
  map.autocomplete '/autocomplete/:type', :controller => 'report',  :action => 'autocomplete'
  map.widget_update '/update_widget/:type.:format', :controller => 'report', :action => 'update_widget'
  map.update_worst_nodes '/update_worst_nodes.:format', :controller => 'report', :action => 'update_worst_nodes'
  # Install the default route as the lowest priority.
  map.connect '', :controller => 'dashboard'
  map.connect ':controller/:action/:id'
  map.connect ':controller/:action/:id.:format'
  #map.connect '*path', :controller => 'application', :action => 'rescue_404'
end
