# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAvailabilityTest < GitHub::TestCase
  def test_nonexist
    assert_equal :nonexist, ::Repository::Availability.new(nil).state
  end

  def test_active
    assert_equal :nonexist, availability(active: nil)
  end

  def test_disabled
    assert_equal :disabled, availability(disabled: true)
  end

  def test_locked
    assert_equal :locked, availability(locked: true, empty: true)
  end

  def test_down
    assert_equal :down, availability(empty: true, offline: true, pushed_at: 1)
  end

  def test_offline
    assert_equal :offline, availability(empty: true, offline: true)
  end

  def test_forking
    assert_equal :forking, availability(empty: true, parent_id: 1)
  end

  def test_mirroring
    assert_equal :mirroring, availability(empty: true, mirror: 1)
  end

  def test_nonexistent
    assert_equal :nonexistent, availability(exists: false)
  end

  def test_ok
    assert_equal :ok, availability
  end

  def test_setting_status
    avail = ::Repository::Availability.new(nil)
    avail.db_state = " nonexist "
    assert_equal :nonexist, avail.db_state
  end

  def test_setting_git_status
    avail = ::Repository::Availability.new(nil)
    avail.git_state = " locked "
    assert_equal :locked, avail.git_state
  end

  def test_forcing_ok_status
    avail = ::Repository::Availability.new(nil)
    avail.db_state = " booya "
    assert_equal :ok, avail.db_state
  end

  def test_forcing_ok_git_status
    avail = ::Repository::Availability.new(nil)
    avail.git_state = " boom "
    assert_equal :ok, avail.git_state
  end

  def test_clearing_status
    avail = ::Repository::Availability.new(nil)
    avail.db_state = " "
    assert_equal :nonexist, avail.db_state
  end

  def test_setting_git_status_empty
    avail = ::Repository::Availability.new(nil)
    avail.git_state = " "
    assert_equal :nonexist, avail.git_state
  end

  def availability(options = nil)
    repo = Repository.new
    options.each do |key, value|
      repo.send "#{key}=", value
    end if options
    ::Repository::Availability.new(repo).state
  end

  class TestGitRepositoryAccess < GitRepositoryAccess
    def initialize(git_repository)
      @type = "repository"

      super
    end
  end

  class Repository
    attr_writer :locked, :empty, :offline, :parent_id, :deleted, :active, :disabled, :route, :exists, :mirror
    attr_accessor :id, :pushed_at, :disabled_at

    def initialize(*)
      @active = true
    end

    def deleted?
      !!@deleted
    end

    def active?
      !!@active
    end

    def disabled?
      !!@disabled
    end

    def locked?
      !!@locked
    end

    def empty?
      !!@empty
    end

    def offline?
      !!@offline
    end

    def parent_id?
      !!@parent_id
    end

    def mirror?
      !!@mirror
    end

    def network_broken?
      false
    end

    def access
      TestGitRepositoryAccess.new(self)
    end

    def route
      return @route if defined?(@route)
      @route = "localhost"
    end

    def exists_on_disk?
      return @exists if defined?(@exists)
      true
    end
  end
end
