# frozen_string_literal: true

require "rails_helper"
require "restraint"

RSpec.describe Restraint do
  include ActiveSupport::Testing::TimeHelpers

  let(:restraint) { described_class.new }
  let(:fake_key) { "fake_key" }

  def cleanup
    0.upto(2) do |n|
      Dependabot.redis.del("#{fake_key}:#{n}")
    end
  end

  before do
    cleanup
  end

  after do
    cleanup
  end

  it "returns the result of the block" do
    expect(restraint.lock!(fake_key, 2, 10) { :tada }).to eq(:tada)
  end

  it "prevents more than a specific number of locks" do
    checkpoint_reached = T.let(false, T::Boolean)
    restraint.lock!(fake_key, 2, 10) do
      restraint.lock!(fake_key, 2, 10) do
        expect { restraint.lock!(fake_key, 2, 10) { true } }.to raise_error(Restraint::UnableToLock)
        checkpoint_reached = true
      end
    end
    expect(checkpoint_reached).to be(true)
  end

  it "releases the lock when complete" do
    expect(restraint.lock!(fake_key, 1, 10) { true }).to be(true)
    expect(restraint.lock!(fake_key, 1, 10) { true }).to be(true)
  end

  it "releases the lock when TTL expires" do
    restraint.lock!(fake_key, 1, 10) do
      # instead of waiting for TTL, expire the key directly:
      Dependabot.redis.expire("#{fake_key}:1", 0)
      # lock should work again:
      expect(restraint.lock!(fake_key, 1, 10) { true }).to be(true)
    end
  end

  it "does not unlock when original lock times out and another process/thread takes the lock" do # rubocop:disable RSpec/ExampleLength
    t1_lock_timed_out_latch = Concurrent::CountDownLatch.new
    t1_can_finish_latch = Concurrent::CountDownLatch.new
    t1_has_finished_latch = Concurrent::CountDownLatch.new

    t1 = Thread.new do
      restraint.lock!(fake_key, 1, 1) do
        sleep 2
        t1_lock_timed_out_latch.count_down
        t1_can_finish_latch.wait
      end
      t1_has_finished_latch.count_down
    end

    t2 = Thread.new do
      t1_lock_timed_out_latch.wait

      restraint.lock!(fake_key, 1, 1) do
        # Assert we have the lock
        expect(restraint.obtain_lock(fake_key, 1, 1)).to be(false)

        # let t1 finish so that we can assert that the lock is still there
        t1_can_finish_latch.count_down
        t1_has_finished_latch.wait

        # Assert we still have the lock
        expect(restraint.obtain_lock(fake_key, 1, 1)).to be(false)
      end
    end

    # Both threads should exit successfully (which means their assertions passed)
    expect(t1.join(5).status).to be(false)
    expect(t2.join(5).status).to be(false)
  end

  context "reentrant locks" do
    it "allows a lock to be reacquired by passing the yielded lock" do # rubocop:disable RSpec/ExampleLength
      checkpoint_reached = T.let(false, T::Boolean)
      obtained_lock = 0
      restraint.lock!(fake_key, 2, 10) do |lock1|
        obtained_lock += 1
        restraint.lock!(fake_key, 2, 10) do |lock2|
          obtained_lock += 1

          expect(lock2).not_to eq(lock1)

          # Normally, this would raise.
          restraint.lock!(fake_key, 2, 10, lock: lock2) do |lock3|
            obtained_lock += 1

            # The same lock has been reused
            expect(lock3).to eq(lock2)

            # We can go even deeper.
            restraint.lock!(fake_key, 2, 10, lock: lock3) do
              obtained_lock += 1
            end

            # But without the lock, we can't.
            expect { restraint.lock!(fake_key, 2, 10) { true } }.
              to raise_error(Restraint::UnableToLock)
            checkpoint_reached = true
          end
        end
      end
      expect(obtained_lock).to eq(4)
      expect(checkpoint_reached).to be(true)
    end

    it "requires a compatible lock instance" do
      checkpoint_reached = T.let(false, T::Boolean)
      restraint.lock!(fake_key, 2, 10) do
        restraint.lock!(fake_key, 2, 10) do
          incompatible = Restraint::Lock.new(key: "nope", value: "1", count: 2, expires_at: 10.minutes.from_now)
          expect { restraint.lock!(fake_key, 2, 10, lock: incompatible) { true } }.
            to raise_error(Restraint::UnableToLock)
          checkpoint_reached = true
        end
      end
      expect(checkpoint_reached).to be(true)
    end

    it "requires a lock instance that currently holds the lock" do
      checkpoint_reached = T.let(false, T::Boolean)

      released_lock = restraint.lock!(fake_key, 2, 10) do |lock|
        expect(lock.held).to be(true)
        lock
      end
      expect(released_lock.held).to be(false)

      restraint.lock!(fake_key, 2, 10) do
        restraint.lock!(fake_key, 2, 10) do
          expect { restraint.lock!(fake_key, 2, 10, lock: released_lock) { true } }.
            to raise_error(Restraint::UnableToLock)
          checkpoint_reached = true
        end
      end
      expect(checkpoint_reached).to be(true)
    end

    it "requires a lock instance that has not expired" do
      checkpoint_reached = T.let(false, T::Boolean)
      restraint.lock!(fake_key, 2, 10) do
        restraint.lock!(fake_key, 2, 10) do |lock|
          travel_to(1.minute.from_now) do
            expect { restraint.lock!(fake_key, 2, 10, lock:) { true } }.
              to raise_error(Restraint::UnableToLock)
            checkpoint_reached = true
          end
        end
      end
      expect(checkpoint_reached).to be(true)
    end
  end
end
