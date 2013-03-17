require 'in_place_editor'
require 'form_helper'
ActionController::Base.send :include, InPlaceEditingPlus
ActionController::Base.helper InPlaceMacrosHelper
ActionView::Base.send :include, InPlaceMacrosHelper
