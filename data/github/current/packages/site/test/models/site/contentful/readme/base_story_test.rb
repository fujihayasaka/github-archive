# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::BaseStoryTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @developer_story_brian = VCR.use_cassette("contentful/readme-developer-story-brian-douglas") do
      Site::Contentful::Readme::DeveloperStory.find("brian-douglas", include_unpublished: true)
    end

    @developer_story_henry = VCR.use_cassette("contentful/readme-developer-story-henry-zhu") do
      Site::Contentful::Readme::DeveloperStory.find("henry-zhu", include_unpublished: true)
    end

    @featured_article = VCR.use_cassette("contentful/readme-featured-article-react") do
      Site::Contentful::Readme::FeaturedArticle.find("react", include_unpublished: true)
    end

    @guide = VCR.use_cassette("contentful/readme-guide-angie-jones-demystifying-developer-advocacy") do
      Site::Contentful::Readme::Guide.find("angie-jones-demystifying-developer-advocacy", include_unpublished: true)
    end

    @featured_article_no_seo = VCR.use_cassette("contentful/readme-featured_article-no-seo-content-model") do
      Site::Contentful::Readme::FeaturedArticle.find("react", include_unpublished: true)
    end

    @podcast = VCR.use_cassette("contentful/readme-podcast-growing-vue") do
      Site::Contentful::Readme::Podcast.find("growing-vue", include_unpublished: true)
    end
  end

  test "#github_user?" do
    assert @developer_story_brian.github_user?
    refute @featured_article.github_user?
  end

  test "#open_source_project? private method" do
    assert @developer_story_brian.send(:open_source_project?)
    refute @featured_article.respond_to?(:open_source_project?)
  end

  test "#open_source_project_path private method" do
    refute @featured_article.respond_to?(:open_source_project_path)
    assert_equal "open-sauced", @developer_story_brian.send(:open_source_project_path)
    assert_equal "babel/babel", @developer_story_henry.send(:open_source_project_path)
  end

  test "#name_with_owner? private method" do
    assert @developer_story_brian.send(:name_with_owner?, "foo/bar")
    refute @developer_story_brian.send(:name_with_owner?, "foo")
    refute @developer_story_brian.send(:name_with_owner?, nil)
  end

  test "#get_url_path private method" do
    assert_equal "foo/bar", @developer_story_brian.send(:get_url_path, "http://github.com/foo/bar")
    assert_equal "foo/bar", @developer_story_brian.send(:get_url_path, "http://github.com/foo/bar?foo=bar")
    assert_equal "foo/bar/foo/bar", @developer_story_brian.send(:get_url_path, "http://github.com/foo/bar/foo/bar")
    assert_nil @developer_story_brian.send(:get_url_path, nil)
  end

  test "#meta_title" do
    @featured_article.seo.stubs(:meta_title).returns("Alternate title")
    @guide.seo.stubs(:meta_title).returns(nil)

    assert_equal "Alternate title", @featured_article.meta_title
    assert_equal @guide.heading, @guide.meta_title
  end

  test "#meta_description" do
    assert_equal @featured_article.seo.meta_description, @featured_article.meta_description
  end

  test "#meta_image" do
    assert_equal @featured_article.seo.meta_image, @featured_article.meta_image
  end

  test "#open_graph_title" do
    @featured_article.seo.stubs(:open_graph_title).returns("Open graph title")
    @guide.seo.stubs(:open_graph_title).returns(nil)

    assert_equal "Open graph title", @featured_article.open_graph_title
    assert_equal @guide.heading, @guide.open_graph_title
  end

  test "#open_graph_description" do
    @featured_article.seo.stubs(:open_graph_description).returns("Open graph description")
    @guide.seo.stubs(:open_graph_description).returns(nil)

    assert_equal "Open graph description", @featured_article.open_graph_description
    assert_equal @guide.seo.meta_description, @guide.open_graph_description
  end

  context "older content model without SEO on stories" do
    test "#meta_title" do
      assert_equal @featured_article_no_seo.heading, @featured_article_no_seo.meta_title
    end

    test "#meta_description" do
      assert_equal @featured_article_no_seo.meta_text, @featured_article_no_seo.meta_description
    end

    test "#meta_image" do
      assert_equal @featured_article_no_seo.fields[:meta_image], @featured_article_no_seo.meta_image
    end

    test "#open_graph_title" do
      assert_equal @featured_article_no_seo.heading, @featured_article_no_seo.open_graph_title
    end

    test "#open_graph_description" do
      assert_equal @featured_article_no_seo.meta_text, @featured_article_no_seo.open_graph_description
    end
  end

  context "#to_json" do
    test "serializes common attributes" do
      [@featured_article, @guide, @developer_story_brian, @podcast].each do |story|
        json = story.to_json

        assert_equal story.category_slug, json[:category_slug]
        assert_equal story.content_type.id, json[:content_type][:id]
        assert_equal story.heading, json[:heading]
        assert_equal story.hero_image.absolute_url, json[:hero_image][:absolute_url]
        assert_equal story.hero_image.url, json[:hero_image][:url]
        assert_equal story.label, json[:label]
        assert_equal story.meta_description, json[:meta_description]
        assert_equal story.meta_image.absolute_url, json[:meta_image][:absolute_url]
        assert_equal story.meta_text, json[:meta_text]
        assert_equal story.meta_title, json[:meta_title]
        assert_equal story.name, json[:name]
        assert_equal story.open_graph_description, json[:open_graph_description]
        assert_equal story.open_graph_title, json[:open_graph_title]
        assert_equal story.publication_date.rfc2822, json[:publication_date_rfc2822]
        assert_equal story.publication_date.iso8601, json[:publication_date_iso8601]
        assert_equal story.published?, json[:published?]
        assert_equal story.slug, json[:slug]
        assert_equal story.subheading, json[:subheading]
        assert_equal story.thumbnail.url, json[:thumbnail][:url]
        assert_equal story.url, json[:url]
      end
    end

    test "returns nil URLs if some images are missing" do
      @guide.stubs(:hero_image).returns(nil)
      @guide.stubs(:thumbnail).returns(nil)

      assert_nil @guide.to_json[:hero_image][:url]
      assert_nil @guide.to_json[:thumbnail][:url]
    end

    test "returns the right podcast? value" do
      assert_equal true, @podcast.to_json[:podcast?]
      assert_equal false, @guide.to_json[:podcast?]
      assert_equal false, @featured_article.to_json[:podcast?]
      assert_equal false, @developer_story_brian.to_json[:podcast?]
    end

    test "returns the right developer_story? value" do
      assert_equal true, @developer_story_brian.to_json[:developer_story?]
      assert_equal false, @guide.to_json[:developer_story?]
      assert_equal false, @featured_article.to_json[:developer_story?]
      assert_equal false, @podcast.to_json[:developer_story?]
    end

    test "returns the right featured_article? value" do
      assert_equal true, @featured_article.to_json[:featured_article?]
      assert_equal false, @guide.to_json[:featured_article?]
      assert_equal false, @developer_story_brian.to_json[:featured_article?]
      assert_equal false, @podcast.to_json[:featured_article?]
    end

    test "returns the right intro value" do
      # Currently, only featured articles have an intro.
      @featured_article.stubs(:intro).returns("Intro text")

      assert_equal @featured_article.intro, @featured_article.to_json[:intro]
      assert_nil @guide.to_json[:intro]
      assert_nil @podcast.to_json[:intro]
      assert_nil @developer_story_brian.to_json[:intro]
    end

    test "returns the right bio value" do
      assert_nil @featured_article.to_json[:bio]
      assert_equal @guide.bio, @guide.to_json[:bio]
      assert_equal @podcast.bio, @podcast.to_json[:bio]
      assert_equal @developer_story_brian.bio, @developer_story_brian.to_json[:bio]
    end

    test "returns the right github_handle value" do
      assert_equal @podcast.github_handle, @podcast.to_json[:github_handle]
      assert_nil @featured_article.to_json[:github_handle]
      assert_nil @guide.to_json[:github_handle]
      assert_nil @developer_story_brian.to_json[:github_handle]
    end

    test "returns the right label value" do
      assert_equal @podcast.label, @podcast.to_json[:label]
      assert_equal @featured_article.label, @featured_article.to_json[:label]
      assert_equal @guide.label, @guide.to_json[:label]
      assert_equal @developer_story_brian.label, @developer_story_brian.to_json[:label]
    end

    test "returns the right hero_image_layout value" do
      assert_equal @developer_story_brian.hero_image_layout, @developer_story_brian.to_json[:hero_image_layout]
      assert_nil @featured_article.to_json[:hero_image_layout]
      assert_nil @guide.to_json[:hero_image_layout]
      assert_nil @podcast.to_json[:hero_image_layout]
    end

    test "returns the right author_role value" do
      assert_equal @guide.author_role, @guide.to_json[:author_role]
      assert_nil @featured_article.to_json[:author_role]
      assert_nil @podcast.to_json[:author_role]
      assert_nil @developer_story_brian.to_json[:author_role]
    end

    test "returns the right hero_background_color value" do
      assert_equal @guide.hero_background_color, @guide.to_json[:hero_background_color]
      assert_nil @featured_article.to_json[:hero_background_color]
      assert_nil @podcast.to_json[:hero_background_color]
      assert_nil @developer_story_brian.to_json[:hero_background_color]
    end

    context "serializing recirculation" do
      test "returns nil if there is no recirculation" do
        assert_nil @featured_article.to_json[:recirculation]
      end

      test "returns recirculation with the right shape if there is one" do
        assert_equal @podcast.to_json[:recirculation], {
          developer_story?: true,
          guide?: false,
          heading: @podcast.recirculation.heading,
          name: @podcast.recirculation.name,
          podcast?: false,
          thumbnail: {
            url: @podcast.recirculation.thumbnail.url,
          },
          url: @podcast.recirculation.url,
        }
      end
    end

    context "serializing github_user" do
      test "returns nil if the story has no github_user" do
        [@guide, @podcast, @featured_article].each do |story|
          assert_nil story.to_json[:github_user]
        end
      end

      test "returns the github_user with the right shape if the story has one" do
        assert_equal @developer_story_brian.to_json[:github_user], {
          blog: @developer_story_brian.github_user.blog,
          first_name: @developer_story_brian.github_user.first_name,
          handle: @developer_story_brian.github_user.handle,
          last_name: @developer_story_brian.github_user.last_name,
          location: @developer_story_brian.github_user.location,
          twitter_handle: @developer_story_brian.github_user.twitter_handle,
          website: @developer_story_brian.github_user.website,
        }
      end
    end

    context "serializing topics" do
      test "use nil for stories not linked to any topic" do
        assert_nil @developer_story_brian.to_json[:topics]
      end

      test "returns the topics linked to the story" do
        assert_equal @guide.topics.count, @guide.to_json[:topics].count
      end
    end

    context "serializing project_name" do
      test "returns nil for stories without a project_name" do
        assert_nil @podcast.to_json[:project_name]
      end

      test "returns the project_name for stories with a project_name" do
        assert_equal @developer_story_brian.project_name, @developer_story_brian.to_json[:project_name]
      end
    end

    context "serializing hosts" do
      test "returns nil if there are no hosts" do
        @podcast.stubs(:hosts).returns(nil)

        assert_nil @podcast.to_json[:hosts]
        assert_nil @guide.to_json[:hosts]
        assert_nil @featured_article.to_json[:hosts]
        assert_nil @developer_story_brian.to_json[:hosts]
      end

      test "returns the hosts with the right shape" do
        json = @podcast.to_json

        assert_equal @podcast.hosts.count, json[:hosts].count

        assert_equal json[:hosts].first, {
          first_name: @podcast.hosts.first.first_name,
          host_bio: @podcast.hosts.first.host_bio,
          host_click_through: @podcast.hosts.first.host_click_through,
          host_photo: {
            url: @podcast.hosts.first.host_photo.url,
          },
          last_name: @podcast.hosts.first.last_name,
        }
      end
    end

    context "serializing artist" do
      test "returns nil if there is no artist" do
        assert_nil @podcast.to_json[:artist]
        assert_nil @developer_story_brian.to_json[:artist]
      end

      test "returns the artist with the right shape" do
        assert_equal @featured_article.to_json[:artist], {
          name: @featured_article.artist.name,
          website: @featured_article.artist.website,
        }
      end
    end

    context "serializing author" do
      test "returns nil if there is no author" do
        assert_nil @podcast.to_json[:author]
        assert_nil @developer_story_brian.to_json[:author]
      end

      test "returns the author with the right shape" do
        assert_equal @featured_article.to_json[:author], {
          first_name: @featured_article.author.first_name,
          # Author entries seem to no longer have handles but there are some VCR cassettes that have them
          # (probably because they were recorded in the past).
          handle: nil,
          last_name: @featured_article.author.last_name,
          photo: {
            url: @featured_article.author.photo&.url,
          },
        }

        assert_equal @guide.to_json[:author], {
          first_name: @guide.author.first_name,
          # Author entries seem to no longer have handles but there are some VCR cassettes that have them
          # (probably because they were recorded in the past).
          handle: @guide.author.handle,
          last_name: @guide.author.last_name,
          photo: {
            url: @guide.author.photo.url,
          },
        }
      end
    end

    context "serializing company" do
      test "returns nil if there is no company" do
        [@developer_story_brian, @podcast, @featured_article].each do |story|
          assert_nil story.to_json[:company]
        end
      end

      test "returns the company with the right shape" do
        assert_equal @guide.to_json[:company], {
          logo: {
            url: @guide.company.logo.url,
          },
          name: @guide.company.name,
        }
      end
    end

    context "serializing audio" do
      test "returns nil if there is no audio" do
        [@developer_story_brian, @guide, @featured_article].each do |story|
          assert_nil story.to_json[:audio]
        end
      end

      test "returns the audio with the right shape" do
        assert_equal @podcast.to_json[:audio], {
          url: @podcast.audio.url,
        }
      end
    end
  end

  context "#good_first_issues" do
    test "returns nil if the story does not have a repository" do
      refute @featured_article.respond_to?(:good_first_issues)
    end

    test "returns nil if the story does have a repository but it does not have recommended good first issues" do
      repository = create(:repository)

      ExploreFeed::RepositoryGoodFirstIssue.stubs(fetch_by_repo_id:
        create(:repository_good_first_issue_collection, issues: []),
      )

      @developer_story_brian.stubs(:repository).returns(repository)

      assert_nil @developer_story_brian.good_first_issues
    end

    test "returns 8 recommended good first issues max" do
      repository = create(:repository)
      label = create(:label, repository: repository)
      issues = create_list(:issue, 10, repository: repository, labels: [label])
      good_first_issues = issues.map { |issue| create(:repository_good_first_issue, issue_id: issue.id) }

      ExploreFeed::RepositoryGoodFirstIssue.stubs(fetch_by_repo_id:
        create(:repository_good_first_issue_collection, issues: good_first_issues),
      )

      @developer_story_brian.stubs(:repository).returns(repository)

      assert_equal @developer_story_brian.good_first_issues.count, 8
    end
  end

  context "#contributing" do
    test "returns nil if the story does not have recommended good first issues" do
      repository = create(:repository)

      ExploreFeed::RepositoryGoodFirstIssue.stubs(fetch_by_repo_id:
        create(:repository_good_first_issue_collection, issues: []),
      )

      @developer_story_brian.stubs(:repository).returns(repository)

      assert_nil @developer_story_brian.contributing
    end

    test "returns the information with the right shape" do
      repository = create(:repository)
      label = create(:label, repository: repository)
      issues = create_list(:issue, 1, repository: repository, labels: [label])
      good_first_issues = issues.map { |issue| create(:repository_good_first_issue, issue_id: issue.id) }

      ExploreFeed::RepositoryGoodFirstIssue.stubs(fetch_by_repo_id:
        create(:repository_good_first_issue_collection, issues: good_first_issues),
      )

      @developer_story_brian.stubs(:repository).returns(repository)

      assert_equal @developer_story_brian.contributing, {
        repository: {
          name: repository.name,
          owner: {
            login: repository.owner.login,
          }
        },
        issues: [
          {
            created_at: issues.first.created_at.iso8601,
            number: issues.first.number,
            permalink: issues.first.permalink,
            title: issues.first.title,
            user: {
              login: issues.first.user.login,
            }
          }
        ]
      }
    end
  end

  context ".body" do
    test "returns nil if the story does not exist" do
      VCR.use_cassette("contentful/readme-base-story-body-for-unexisting-story") do
        assert_nil Site::Contentful::Readme::FeaturedArticle.body("this-story-does-not-exist")
      end
    end

    test "returns the body for existing stories" do
      VCR.use_cassette("contentful/readme-base-story-body-for-existing-story") do
        assert_equal @featured_article.body, Site::Contentful::Readme::FeaturedArticle.body(@featured_article.slug)
      end
    end
  end

  context "#published?" do
    test "returns false if the story is not published yet" do
      future_date_in_readme_time_zone = DateTime.parse("2042-03-14T08:00:00+00:00").in_time_zone(Site::Contentful::Readme::BaseStory::PUBLICATION_DATE_TIME_ZONE)

      @developer_story_brian.stubs(:publication_date).returns(future_date_in_readme_time_zone)

      Timecop.freeze("2023-03-14T08:00:00+00:00".in_time_zone(Site::Contentful::Readme::BaseStory::PUBLICATION_DATE_TIME_ZONE)) do
        refute @developer_story_brian.published?
      end
    end

    test "returns true for stories already published" do
      past_date_in_readme_time_zone = DateTime.parse("2020-03-14T08:00:00+00:00").in_time_zone(Site::Contentful::Readme::BaseStory::PUBLICATION_DATE_TIME_ZONE)

      @developer_story_brian.stubs(:publication_date).returns(past_date_in_readme_time_zone)

      Timecop.freeze("2023-03-14T08:00:00+00:00".in_time_zone(Site::Contentful::Readme::BaseStory::PUBLICATION_DATE_TIME_ZONE)) do
        assert @developer_story_brian.published?
      end
    end

    test "returns true for stories that are just published" do
      publication_date = DateTime.parse("2020-03-14T08:00:00+00:00").in_time_zone(Site::Contentful::Readme::BaseStory::PUBLICATION_DATE_TIME_ZONE)

      @developer_story_brian.stubs(:publication_date).returns(publication_date)

      Timecop.freeze(publication_date) do
        assert @developer_story_brian.published?
      end
    end
  end
end
