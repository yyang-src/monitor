require 'action_view/helpers/tag_helper'
module InPlaceMacrosHelper
  def in_place_editor_field(object, method, tag_options = {}, in_place_editor_options = {})
    in_place_editor_options[:collection] ||= tag_options[:collection]
    obj = ::ActionView::Helpers::InstanceTag.new(object, method, self).object
    value = obj.send(method)
    attr_type = obj.class.columns_hash[method.to_s].type

    # Add to_html to text field automatically
    formats = tag_options[:formats]
    # no need to_html (2010.5.28)
    #formats = ((formats||"").split(".") << "to_html").uniq.join(".") if attr_type==:text
    final = InPlaceEditingPlus.format(value, formats)

    if attr_type == :boolean || in_place_editor_options[:collection]
      c = in_place_editor_options[:collection]
      text = InPlaceEditingPlus.find_text_by_value(c, value)
      tag_options[:text] = (text != false and text.blank? ? final : text)
      in_place_editor_options[:collection] = InPlaceEditingPlus.format_for_return_text(c)
      in_place_editor_options[:value] = InPlaceEditingPlus.combine_value_and_text(value, text)

      in_place_drop_down_list_field object, method, tag_options , in_place_editor_options



    else
      #FIXME(2010.5.28)
      if attr_type == :datetime #or (attr_type == :text and not tag_options[:hover] == false)
        if attr_type == :datetime
          d = value.blank? ? "" : value.to_s(time_format = tag_options.delete(:format) || :long)
          tag_options[:only_date] = true if time_format.to_s == "date"
        else
          d = final
        end
        sid, eid, lid = "show_#{method}", "edit_#{method}","link_#{method}"
        to_show = "Element.show('#{sid}');Element.show('#{lid}');Element.hide('#{eid}')"
        to_edit = "Element.hide('#{sid}');Element.hide('#{lid}');Element.show('#{eid}')"

        %{<span id='#{sid}'>#{d}</span>
          <span id='#{lid}'>#{link_to_function t(:edit), to_edit}</span>
          
          <span id='#{eid}' style="display:none">
            #{form_remote_tag(:url=>url_for(:action=>"set_#{object}_#{method}", :id=>obj.id, :formats => tag_options[:formats]), 
        :html=>{:class=>"inplaceeditor-form"}, :update => sid, :complete => to_show)}
            #{attr_type == :datetime ? date_field_tag(:value, d, tag_options) : text_area_tag(:value, value)}
            #{"<br>" if attr_type == :text}
            #{submit_tag(t(:submit))}
            #{link_to_function t(:cancel),to_show }
            </form>
          </span>
        }
      else

        return (value.blank? ? value : final) if tag_options[:enabled] == false
        #deal with methods need to called before display
        if not tag_options[:text].blank? or not formats.blank? or value.blank?
          in_place_editor_options[:load_text_url] = in_place_editor_options[:load_text_url] || url_for({ :action => "get_#{object}_#{method}", :id => obj.id })
        end
        if not formats.blank?
          in_place_editor_options[:url] = in_place_editor_options[:url] || url_for({ :action => "set_#{object}_#{method}", :id => obj.id, :formats => formats})
        end

        #set size of editor
        if attr_type == :text or tag_options[:input]==:textarea
          in_place_editor_options[:rows] = 4
          in_place_editor_options[:cols] = 80
        else
          size = ((not value.instance_of?(String) or value.blank?) ? 0 : value.size)
          if size > 80
            in_place_editor_options[:rows] = value.size / 80
            in_place_editor_options[:cols] = 80
          else
            in_place_editor_options[:cols] = size + 10
          end
        end

        tag_options[:text] = final if tag_options[:text].blank?
        default_in_place_editor_field object, method, tag_options , in_place_editor_options
      end
    end
  end
  
  def in_place_drop_down_list_field(object, method, tag_options = {}, in_place_editor_options = {})
    tag = ::ActionView::Helpers::InstanceTag.new(object, method, self)
    tag_options = {:tag => "span", :id => "#{object}_#{method}_#{tag.object.id}_in_place_editor", :class => "in_place_editor_field", :title => I18n.t("Click to edit")}.merge!(tag_options)
    in_place_editor_options[:url] = in_place_editor_options[:url] || url_for({ :action => "set_#{object}_#{method}", :id => tag.object.id })
    tag.to_content_tag(tag_options.delete(:tag), tag_options) + in_place_drop_down_list_editor(tag_options[:id], in_place_editor_options)
  end

  def in_place_drop_down_list_editor(field_id, options = {})
    # here is a bug: after updated one time, the default value will not changed anymore unless refresh the whole page
    function =  "new Ajax.InPlaceCollectionEditor("
    function << "'#{field_id}', "
    function << "'#{url_for(options[:url])}',"
    function << "{collection: #{options[:collection].to_json}, value:'#{options[:value]}'}"
    js_options = {}
    js_options['cancelText'] = %('#{options[:cancel_text]}') if options[:cancel_text]
    js_options['okText'] = %('#{options[:save_text]}') if options[:save_text]
    js_options['loadingText'] = %('#{options[:loading_text]}') if options[:loading_text]
    js_options['savingText'] = %('#{options[:saving_text]}') if options[:saving_text]
    js_options['rows'] = options[:rows] if options[:rows]
    js_options['cols'] = options[:cols] if options[:cols]
    js_options['size'] = options[:size] if options[:size]
    js_options['externalControl'] = "'#{options[:external_control]}'" if options[:external_control]
    js_options['loadTextURL'] = "'#{url_for(options[:load_text_url])}'" if options[:load_text_url]
    js_options['ajaxOptions'] = options[:options] if options[:options]
    js_options['evalScripts'] = options[:script] if options[:script]
    #js_options['htmlResponse'] = !options[:script] if options[:script]
    js_options['callback'] = "function(form) { return #{options[:with]} }" if options[:with]
    js_options['clickToEditText'] = %('#{I18n.t("Click to edit")}')
    function << (', ' + options_for_javascript(js_options)) unless js_options.empty?
    function << ')'
    javascript_tag(function)
  end

  def in_place_editor(field_id, options = {})
    function =  "new Ajax.InPlaceEditor("
    function << "'#{field_id}', "
    function << "'#{url_for(options[:url])}'"

    js_options = {}

    if protect_against_forgery?
      options[:with] ||= "Form.serialize(form)"
      options[:with] += " + '&authenticity_token=' + encodeURIComponent('#{form_authenticity_token}')"
    end

    js_options['cancelText'] = %('#{options[:cancel_text]}') if options[:cancel_text]
    js_options['okText'] = %('#{options[:save_text]}') if options[:save_text]
    js_options['loadingText'] = %('#{options[:loading_text]}') if options[:loading_text]
    js_options['savingText'] = %('#{options[:saving_text]}') if options[:saving_text]
    js_options['rows'] = options[:rows] if options[:rows]
    js_options['cols'] = options[:cols] if options[:cols]
    js_options['size'] = options[:size] if options[:size]
    js_options['externalControl'] = "'#{options[:external_control]}'" if options[:external_control]
    js_options['loadTextURL'] = "'#{url_for(options[:load_text_url])}'" if options[:load_text_url]
    js_options['ajaxOptions'] = options[:options] if options[:options]

    js_options['htmlResponse'] = false #!options[:script] if options[:script]
    js_options['callback']   = "function(form) { return #{options[:with]} }" if options[:with]
    js_options['clickToEditText'] = %('#{I18n.t("Click to edit")}')# if options[:click_to_edit_text]
    js_options['textBetweenControls'] = %('#{options[:text_between_controls]}') if options[:text_between_controls]
    function << (', ' + options_for_javascript(js_options)) unless js_options.empty?
    function << ')'
    javascript_tag(function)
  end

  # Renders the value of the specified object and method with in-place editing capabilities.
  def default_in_place_editor_field(object, method, tag_options = {}, in_place_editor_options = {})
    tag = ::ActionView::Helpers::InstanceTag.new(object, method, self)
    tag_options = {:tag => "span", :id => "#{object}_#{method}_#{tag.object.id}_in_place_editor", :class => "in_place_editor_field"}.merge!(tag_options)
    in_place_editor_options[:url] = in_place_editor_options[:url] || url_for({ :action => "set_#{object}_#{method}", :id => tag.object.id })
    tag.to_content_tag(tag_options.delete(:tag), tag_options) +
      in_place_editor(tag_options[:id], in_place_editor_options)
  end
end
