# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Startups::Pages::Partners < Site::Contentful::Page
  def cache_key
    "site.swp.startups.partners"
  end

  def fetch_data_from_contentful
    partners = Site::Contentful::Marketing::Startups::StartupPartner.all
    page_data = Site::Contentful::Marketing::Page.find("startup-partners")

    {
      partners: partners.map(&:to_json),
      page_data: page_data_to_json(page_data)
    }
  end

  def page_data_to_json(page)
    {
      title: page.title,
      seo_title: page.seo.title,
      seo_description: page.seo.description,
      seo_image_url: page.seo.image.url,
      heading: page.content.heading
    }
  end
end
