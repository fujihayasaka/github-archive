# typed: false
# frozen_string_literal: true

module StarsListHelper
  def type_for(repo)
    result = if repo.mirror?
      "Mirror"
    elsif repo.private?
      "Private"
    end

    result || ""
  end

  def css_for(repo)
    [
      class_for_public_repos(repo),
      class_for_forked_repos(repo),
      class_for_repos_with_mirrors(repo),
    ].join(" ")
  end

  def sort_info_for(sort_type, star)
    starrable = star.try(:starrable) || star

    case sort_type
    when "created"
      safe_join(["Starred ", time_ago_in_words_js(star.created_at)])
    when "stars"
      pluralize(number_with_delimiter(starrable.stargazer_count), "star")
    else
      if star.for_topic?
        safe_join(["Last starred ", time_ago_in_words_js(starrable.updated_at)])
      elsif star.for_repository?
        if starrable.pushed_at.nil?
          "Not yet updated"
        else
          safe_join(["Last updated ", time_ago_in_words_js(starrable.pushed_at)])
        end
      end
    end
  end

  private

  def class_for_public_repos(repo)
    if repo.public?
      "public"
    else
      "private"
    end
  end

  def class_for_forked_repos(repo)
    if repo.fork?
      "fork"
    else
      "source"
    end
  end

  def class_for_repos_with_mirrors(repo)
    if repo.mirror?
      "mirror"
    end
  end
end
