# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Podcast < Site::Contentful::Readme::BaseStory
  def self.category_slug
    "podcast"
  end

  def self.content_type
    "podcast"
  end

  def self.sparse_fields_for_index
    %w(seasonNumber episodeNumber guests heading heroImage publicationDate slug subheading thumbnail topics)
  end

  def self.all(**args)
    super(order: "-fields.publicationDate,-fields.seasonNumber,-fields.episodeNumber", **args)
  end

  def name
    return "" if guests.nil?
    names = T.must(guests).map { |guest| "#{guest.first_name} #{guest.last_name}".strip }
    names.compact.to_sentence
  end

  def github_handle
    open_source_project_path || guests&.first.handle
  end

  def label
    if season_number.blank?
      "THE README PODCAST // EPISODE #{episode_number}"
    else
      "THE README PODCAST // S#{season_number}.#{episode_number}"
    end
  end

  def repository
    return unless name_with_owner?(open_source_project_path)

    Repositories.domain.by_qualified_name(open_source_project_path)
  end

  memoize def good_first_issues
    return nil if repository.blank?

    issues = ExploreFeed::RepositoryGoodFirstIssue.fetch_by_repo_id(repository.id)

    recommended_good_first_issues = issues.recommendable.first(MAX_GOOD_FIRST_ISSUES)

    return nil if recommended_good_first_issues.empty?

    recommended_good_first_issues
  end

  # NOTE: This is a temporary method until we have a new Page model for each story's page.
  # Then, we will create this view-friendly data structure directly from there instead
  # of placing it here.
  def contributing
    return nil if good_first_issues.blank?

    {
      repository: {
        name: repository.name,
        owner: {
          login: repository.owner.display_login,
        }
      },
      issues: good_first_issues.map do |issue|
        {
          created_at: issue.created_at.iso8601,
          number: issue.number,
          permalink: issue.permalink,
          title: issue.title,
          user: {
            login: issue.user.display_login,
          }
        }
      end
    }
  end

  def to_json
    {
      audio: if audio.present?
               {
                  url: audio&.url,
               }
             else
               nil
             end,
      bio: bio,
      category_slug: category_slug,
      content_type: {
        id: content_type.id
      },
      developer_story?: developer_story?,
      featured_article?: featured_article?,
      github_handle: github_handle,
      heading: heading,
      hero_image: {
        absolute_url: hero_image&.absolute_url,
        url: hero_image&.url,
      },
      hosts: hosts&.map do |host|
        {
          first_name: host.first_name,
          host_bio: host.host_bio,
          host_click_through: host.host_click_through,
          host_photo: {
            url: host.host_photo.url,
          },
          last_name: host.last_name,
        }
      end,
      label: label,
      meta_description: meta_description,
      meta_image: {
        absolute_url: meta_image&.absolute_url,
      },
      meta_text: meta_text,
      meta_title: meta_title,
      name: name,
      open_graph_description: open_graph_description,
      open_graph_title: open_graph_title,
      podcast?: podcast?,
      project_name: project_name,
      publication_date_rfc2822: publication_date&.rfc2822,
      publication_date_iso8601: publication_date&.iso8601,
      published?: published?,
      recirculation: if recirculation.present?
                       {
                         developer_story?: recirculation&.developer_story?,
                         guide?: recirculation&.guide?,
                         heading: recirculation&.heading,
                         name: recirculation&.name,
                         podcast?: recirculation&.podcast?,
                         thumbnail: {
                           url: recirculation&.thumbnail&.url,
                         },
                         url: recirculation&.url,
                       }
                     else
                       nil
                     end,
      slug: slug,
      subheading: subheading,
      thumbnail: {
        url: thumbnail&.url,
      },
      topics: topics&.map(&:to_json),
      url: url,
      updated_at: updated_at.iso8601,
      klass: self.class.name,
    }
  end

  private

  def open_source_project?
    respond_to?(:open_source_project) && open_source_project.present?
  end

  def open_source_project_path
    return unless open_source_project.present?

    @open_source_project_path ||= get_url_path(open_source_project.url)
  end
end
