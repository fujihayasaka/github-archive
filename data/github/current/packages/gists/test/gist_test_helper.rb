# typed: false
# frozen_string_literal: true

module GistTestHelper
  def gist_test_content_array
    [
      { name: "1", value: "random content" },
    ]
  end

  def self.included(base)
    base.fixtures do
      @user         = create(:verified_user)
      @user2        = create(:verified_user)
      @spammer      = create(:verified_user, spammy: true)
      @staff        = create :staff_admin_user, login: "staffy"
      @staff.emails.first.verify!
      @gist         = GistHelpers.generate \
        contents: gist_test_content_array,
        user: @user, public: false
      @spam_gist    = GistHelpers.generate \
        contents: gist_test_content_array, user: @spammer, public: true

      @anon_gist = GistHelpers.generate \
        contents: gist_test_content_array, public: true, creator_ip: "1.2.3.4"

      @disabled_gist = GistHelpers.generate(contents: gist_test_content_array, user: @user)
      @disabled_gist.access.disable("size", @staff)

      @public_gist  = GistHelpers.generate \
        contents: gist_test_content_array,
        user: @user,
        description: "my gist",
        created_at: 4.hours.ago,
        updated_at: 4.hours.ago
      @secret_gist  = GistHelpers.generate \
        contents: gist_test_content_array,
        user: @user,
        description: "my secret gist",
        public: false
      @deleted_gist = GistHelpers.generate_deleted \
        contents: gist_test_content_array,
        user: @user,
        public: true

      @other_user_gist = GistHelpers.generate \
        contents: gist_test_content_array,
        user: @user2,
        public: true
    end
  end
end
