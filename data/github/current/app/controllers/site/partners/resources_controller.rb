# typed: true
# frozen_string_literal: true

class Site::Partners::ResourcesController < Site::BaseController
  layout "site"
  javascript_bundle "technology-partners"

  INDEX_VIEW     = "site/partners/resources/index"
  SHOW_VIEW_PATH = "site/partners/integration_resources"

  # Please do not copy or replicate this code. We're disabling linting rule to allow dynamic template rendering for the TPE site migration. We have consulted the marketing-engineering team and we have been instructed to do so. You can read more about the project at this issue https://github.com/github/technology-partnerships-and-engineering/issues/3189
  def index
    page_title        = "Resources"
    hero_text         = <<~EOS
      We hope you find this curated list of resources helpful. Every effort
      for accuracy has been made, but the fast pace of business and technology
      can make links and references outdated.
    EOS

    resource_files    = Dir.glob(Rails.root.join("app", "views", SHOW_VIEW_PATH, "*.html.erb"))
    posts             = []
    all_categories    = []
    category_tags_map = {}

    resource_files.each do |file|
      content        = File.read(file) rescue ""
      title_match    = content.match(/post_title\s*=\s*['"](.+?)['"]/)
      categories     = extract_array(content, /post_categories\s*=\s*\[(.*?)\]/m)
      tags           = extract_array(content, /post_tags\s*=\s*\[(.*?)\]/m)
      priority_match = content.match(/post_priority\s*=\s*(\d+)/)
      sections       = extract_array(content, /post_sections\s*=\s*\[(.*?)\]/m)
      type_match     = content.match(/post_type\s*=\s*['"](.+?)['"]/)
      preview_match  = content.match(/post_preview\s*=\s*['"](.+?)['"]/)

      all_categories.concat(categories)
      categories.each do |cat|
        category_tags_map[cat] ||= []
        category_tags_map[cat].concat(tags)
      end

      posts << {
        title:      (title_match ? title_match[1] : File.basename(file, ".html.erb").titleize),
        categories: categories,
        tags:       tags,
        priority:   (priority_match ? priority_match[1].to_i : 999),
        sections:   sections,
        type:       (type_match ? type_match[1] : nil),
        preview:    (preview_match ? preview_match[1] : nil),
        slug:       File.basename(file, ".html.erb"),
        file_path:  file
      }
    end

    categories = all_categories.uniq.sort
    category_tags_map.each { |k, v| category_tags_map[k] = v.uniq.sort }

    render INDEX_VIEW,
      locals: {
        page_title:        page_title,
        hero_text:         hero_text,
        posts:             posts,
        categories:        categories,
        category_tags_map: category_tags_map
      }
  end

  # rubocop:disable GitHub/RailsViewRenderPathsExist, GitHub/RailsControllerRenderLiteral
  def show
    template = "#{SHOW_VIEW_PATH}/#{params[:id]}"

    if lookup_context.find_all(template).any?
      render template: template
    else
      render_404
    end
  end

  private

  def extract_array(content, regexp)
    if (m = content.match(regexp))
      m[1].scan(/['"]([^'"]+)['"]/).flatten
    else
      []
    end
  end
end
