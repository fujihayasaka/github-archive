# typed: true
# frozen_string_literal: true

# Frontend check related helper methods.
module ChecksHelper
  # Produces an appropriately sized check output image URL.
  #
  # original_url  - Original image URL you want to display.
  # proxied       - Whether the returned URL should be proxied through our image proxy service.
  #                 Use this if the URL is going to be used to insert an img tag, otherwise
  #                 our Content Security Policy will block the image.
  #
  # Returns a String.
  def check_run_image_url_for(original_url, proxied: true)
    url = original_url
    if proxied && url.present?
      GitHub::HTML::CamoFilter.asset_proxy_url(url)
    else
      url
    end
  end

  def check_run_state_description(check_run)
    return actions_check_run_state_description(check_run) if check_run.is_actions_check_run?

    # We don't have default values for StatusCheckConfig when conclusion is nil,
    # consider implementing that in the future
    return "This check is #{check_run.status.humanize(capitalize: false)}" if check_run.conclusion.nil?

    StatusCheckConfig.conclusion_for(check_run.conclusion)&.sentence_for_check
  end

  # This method is nearly a duplicate of check_run_state_description but uses the
  # terminology "job" instead of "check".
  def actions_check_run_state_description(check_run)
    # We don't have default values for StatusCheckConfig when conclusion is nil,
    # consider implementing that in the future
    return "This job is #{check_run.status.humanize(capitalize: false)}" if check_run.conclusion.nil?

    StatusCheckConfig.conclusion_for(check_run.conclusion)&.sentence_for_job
  end

  def check_run_state_icon(conclusion, status)
    # override the default here for WAITING, which is normally an 'dot-fill'
    # The StatusCheckConfig keeps a normative definition of all the icons/colors/ect
    # But in some places we need to overide these app wide defaults.
    return "clock" if status == StatusCheckConfig::WAITING
    # We don't have default values for StatusCheckConfig when conclusion is nil,
    # consider implementing that in the future
    return "dot-fill" unless conclusion

    StatusCheckConfig.conclusion_for(conclusion)&.icon
  end

  def annotation_message(message)
    GitHub::Goomba::ActionsAnnotationPipeline.to_html(message)
  end
end
