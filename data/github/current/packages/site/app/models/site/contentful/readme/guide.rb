# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Guide < Site::Contentful::Readme::BaseStory
  def self.category_slug
    "guides"
  end

  def self.content_type
    "guide"
  end

  def self.sparse_fields_for_index
    %w(author company heading heroImage publicationDate slug subheading thumbnail topics)
  end

  def name
    "#{author&.first_name} #{author&.last_name}".strip
  end

  def project_name
    return unless company.present?

    company.name
  end

  def label
    [name, project_name].compact.join(" // ")
  end

  def to_json
    {
      artist: {
        name: artist&.name,
        website: artist&.website,
      },
      author: {
        first_name: author&.first_name,
        # Author entries seem to no longer have handles but there are some VCR cassettes that have them
        # (probably because they were recorded in the past).
        handle: author&.respond_to?(:handle) ? author.handle : nil,
        last_name: author&.last_name,
        photo: {
          url: author&.photo&.url,
        },
      },
      author_role: author_role,
      bio: bio,
      category_slug: category_slug,
      company: {
        logo: {
          url: company&.logo&.url,
        },
        name: company&.name,
      },
      content_type: {
        id: content_type.id
      },
      developer_story?: developer_story?,
      featured_article?: featured_article?,
      github_handle: github_handle,
      heading: heading,
      hero_background_color: hero_background_color,
      hero_image: {
        absolute_url: hero_image&.absolute_url,
        url: hero_image&.url,
      },
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
end
