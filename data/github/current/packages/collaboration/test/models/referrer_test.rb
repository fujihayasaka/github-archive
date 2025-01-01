# typed: false
# frozen_string_literal: true

require "test_helper"

class ReferrerTest < GitHub::TestCase
  module Callbackable
    def self.included(base)
      class << base
        attr_accessor :callback
        def after_save(cb, opts = {}) @callback = cb end
        def after_commit(cb, opts = {}) @callback = cb end
        def before_save(cb, opts = {}) end
      end
    end
  end

  class ReferringRecord
    include Callbackable
    include Referrer
    setup_referrer

    attr_accessor :user
    attr_accessor :editor
    attr_accessor :updated_at

    def saved_change_to_body?
      true
    end

    # Fake out enough of our UserContent contract for Referrer to work
    def mentioned_issues
      @mentioned_issues ||= []
    end
    attr_writer :mentioned_issues
  end

  class TestReferenceable
    attr_accessor :referrer, :user, :time

    def record_reference_from(referrer, user, time)
      @referrer, @user, @time = referrer, user, time
    end
  end

  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @repo = create :repository, owner: @user
    @issue1 = create :issue, repository: @repo, user: @user
    @issue2 = create :issue, repository: @repo, user: @user
  end

  setup do
    @callback = Referrer::ReferenceMentionsCallback.new
    @referrer = ReferringRecord.new
    @referrer.user = @user
    @refable = TestReferenceable.new
    @referrer.mentioned_issues << @refable
  end

  test "must be setup" do
    referrer = Class.new do
      include Callbackable
      include Referrer
    end
    assert_nil referrer.callback

    referrer.setup_referrer
    assert_kind_of Referrer::ReferenceMentionsCallback, referrer.callback
  end

  context "referrer" do
    test "defaults to self" do
      assert_equal @referrer, @referrer.referrer
    end
  end

  context "referring_actor" do
    test "defaults to user" do
      @referrer.user = @user
      assert_equal @user, @referrer.referring_actor
    end

    test "returns editor if present" do
      @referrer.stubs(:repository).returns(@repo)

      @referrer.user = @user
      @referrer.editor = @other_user
      assert_equal @other_user, @referrer.referring_actor
    end
  end

  context "track_references" do
    test "defaults to true" do
      assert_predicate @referrer, :track_references?
    end
  end

  context "track_references_in_background?" do
    test "defaults to false" do
      refute_predicate @referrer, :track_references_in_background?
    end
  end

  context "after_save callback" do
    test "responds to after_save" do
      assert @callback.respond_to? :after_save
    end

    test "creates references for mentions" do
      Referenceable.expects(:batch_record_references_from).with([@refable], @referrer, @user, nil).returns(nil)

      assert @callback.track_references!(@referrer)
    end

    test "skips references from nil actors" do
      @referrer.user = nil
      @callback.track_references!(@referrer)
      assert_nil @refable.referrer
    end

    test "finds all mentioned referenceables" do
      assert_equal [@refable],
        @referrer.mentioned_referenceables
    end
  end

  context "after_commit callback" do
    test "responds to after_commit" do
      assert @callback.respond_to? :after_commit
    end

    test "enqueues job to creates references for mentions" do
      @referrer.stub(:track_references_in_background?, true) do
        ProcessMentionedReferencesJob.expects(:perform_later).with(@referrer, @referrer.updated_at)

        @callback.track_references!(@referrer)
      end
    end

    test "only enqueues job if the reference doesn't exist" do
      GitHub.flipper[:check_reference_exists].enable

      ActiveRecord::Relation.any_instance.stubs(:exists?).returns(true)

      @referrer.stub(:track_references_in_background?, true) do
        ProcessMentionedReferencesJob.expects(:perform_later).times(0)
        @callback.track_references!(@referrer)
      end
    end
  end
end
