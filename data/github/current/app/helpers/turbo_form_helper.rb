# typed: true
# frozen_string_literal: true

# Overrides for Form Helpers to provide default properties for Turbo
#
# By default, we want to opt out of Turbo for all form tags
#
module TurboFormHelper
  include Kernel

  def form_for(record, options = {}, &block)
    options = apply_turbo_form_options(options)
    if block_given?
      super(record, options) do |f|
        block.call(f)
      end
    else
      super(record, options)
    end
  end

  def form_with(model: false, scope: nil, url: nil, format: nil, **options, &block)
    options = apply_turbo_form_options(options)

    if block_given?
      super(model: model, scope: scope, url: url, format: format, **options) do |f|
        block.call(f)
      end
    else
      super(model: model, scope: scope, url: url, format: format, **options)
    end
  end

  def form_tag(url_for_options = {}, options = {}, &block)
    options = apply_turbo_form_options(options)
    if block_given?
      super(url_for_options, options) do |f|
        block.call(f)
      end
    else
      super(url_for_options, options)
    end
  end

  def button_to(name = nil, options = nil, html_options = nil, &block)
    html_options, options = options, name if block_given?
    options ||= {}
    html_options ||= {}
    html_options = html_options.stringify_keys

    html_options["form"] = apply_turbo_form_options(html_options["form"])

    if block_given?
      super(options, html_options) do |f|
        block.call(f)
      end
    else
      super(name, options, html_options)
    end
  end

  private

  def apply_turbo_form_options(options = {})
    options ||= {}
    options[:data] ||= {}
    options[:data][:turbo] ||= options["data-turbo"] || "false"

    # Delete potentially conflicting "data-turbo" key
    options.delete("data-turbo")

    options
  end

end
