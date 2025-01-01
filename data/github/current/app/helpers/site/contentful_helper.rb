# typed: true
# frozen_string_literal: true

module Site::ContentfulHelper
  # to make adding json object fields easier for editors,
  # json object fields in Contentful in the format of {text: "...", href: '...'}
  # and so we'll have a helper here convert the keys to the arguments expected by the corresponding ViewComponent
  def convert_keys_for_cta(contentful_cta_field)
    return [] unless contentful_cta_field.present? && contentful_cta_field.is_a?(Array)

    contentful_cta_field.map { |field| { text: field[:text], url: field[:href] } }
  end
end
