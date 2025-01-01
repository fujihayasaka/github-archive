# typed: false
# frozen_string_literal: true

class Devtools::Spamurai::PatternsController < DevtoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required
  before_action :sudo_filter

  def queues # rubocop:todo GitHub/UseRestfulActions
    @current_data_patterns           = Spam.get_current_patterns("data")
    @current_filename_patterns       = Spam.get_current_patterns("filename")
    @current_gist_patterns           = Spam.get_current_patterns("gist")
    @current_gist_comment_patterns   = Spam.get_current_patterns("gist_comment")
    @current_pages_js_patterns       = Spam.get_current_patterns("pages_js")
    @current_wiki_patterns           = Spam.get_current_patterns("wiki")

    render "devtools/spamurai/patterns/queues"
  end

  def add_queue_pattern # rubocop:todo GitHub/UseRestfulActions
    key = params[:key]
    unless %w[commit_comment data email filename gist issue
            issue_comment pages_js repositories wiki].include? key
      flash[:error] = "Unrecognized key: #{key}"
      redirect_to :back
      return
    end

    pattern = params[:pattern].to_s

    regexp = validate_pattern(pattern)
    # We've encountered an error state, return so the flash/redirect can process
    return if regexp.nil?

    result = Spam.add_current_pattern(key, regexp)
    if result
      GitHub::SpamChecker.notify("%s added pattern '%s' to '%s'" %
                                  [current_user, pattern, key])
      flash[:notice] = "Pattern '%s' added to '%s'" %
                        [pattern, key]
    else
      GitHub::SpamChecker.notify("%s failed to add pattern '%s' to '%s'" %
                                  [current_user, pattern, key])
      flash[:notice] = "Pattern addition failed for '%s' in '%s'", %
                        [pattern, key]
    end

    redirect_to :back
  end

  def remove_queue_pattern # rubocop:todo GitHub/UseRestfulActions
    key = params[:key]
    pattern = params[:pattern]
    result = Spam.remove_current_pattern(key, pattern)
    if result
      GitHub::SpamChecker.notify("%s removed pattern '%s' from '%s'" %
                                  [current_user, pattern, key])
      flash[:notice] = "Pattern '#{pattern}' removed from '#{key}'"
    else
      GitHub::SpamChecker.notify("%s failed to remove pattern '%s' from '%s'" %
                                  [current_user, pattern, key])
      flash[:notice] = "Pattern removal failed for '#{pattern}' in '#{key}'"
    end
    redirect_to :back
  end

  private

  def pattern_params
    params.require(:spam_pattern).permit(:pattern, :class_name, :attribute_name, :flag, :log, :queue, :comment)
  end

  # Private: Validate the staff supplied regexp
  #
  # Returns a Regexp if valid
  # redirects and shows a flash otherwise
  def validate_pattern(pattern)
    # Make this concession to the inevitable confusion I'll have when I paste
    # in a canonical Regexp form into the field and find its ending tags
    # escaped.
    if pattern !~ /\A\/(.+)\/([imx]{0,3})\z/
      flash[:error] = "Unrecognized Regexp format: #{pattern}"
      redirect_to :back
      return
    end

    pattern     = Regexp.last_match[1].dup    # grab a copy before these go away
    flag_string = Regexp.last_match[2].dup

    flags  = 0
    flags |= Regexp::EXTENDED   if flag_string =~ /x/
    flags |= Regexp::IGNORECASE if flag_string =~ /i/
    flags |= Regexp::MULTILINE  if flag_string =~ /m/

    begin
      regexp = Regexp.new pattern, flag_string
    rescue RegexpError => e
      flash[:notice] = "Pattern '#{pattern}' (#{flag_string}) wasn’t a valid Regexp: #{e}"
      redirect_to :back
      return
    end

    regexp
  end

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil,
      label: "Queued Patterns",
      path: queues_spamurai_patterns_path,
      parent: ContextRegion::Devtools::SpamuraiCrumb.new
    )
  end
end
