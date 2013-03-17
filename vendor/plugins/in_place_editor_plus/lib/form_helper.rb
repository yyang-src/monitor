module ActionView
  module Helpers
    class InstanceTag
      def to_content_tag(tag_name, options = {})
        content_tag(tag_name, options[:text] || value(object).to_s , options)
      end
    end
  end
end