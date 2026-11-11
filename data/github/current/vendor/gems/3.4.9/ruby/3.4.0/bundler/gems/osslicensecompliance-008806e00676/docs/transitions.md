# Creating and running transitions

[Transitions](https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/) are used to backfill, update, or delete data. These are a bit different from migrations, which change the shape of the database schema. (For migrations, we use Skeefree.)

The following sections will tell you how to create and run a transition, step by step.

## 1. Write the transition code

As of this writing (October 2025), the `Storage` struct does not expose its `*sql.DB` directly. So, you'll likely need to extend `Storage` to include the specific data manipulations you wish to do.

You'll then wire that up in [internal/transitions.go](https://github.com/github/osslicensecompliance/blob/main/internal/transitions/transitions.go), much like the `check` transition.

[This pull request](https://github.com/github/osslicensecompliance/pull/346) was the first transition in OLC. It's _very_ simple. A little too simple, but it shows the basic parts.

It's too simple, because the transitions documentation recommends having a `--write` flag that's required to actually run the transition. Without that flag, it's expected to be a dry run (just logging what it _would_ do). Also, transitions may need to have the ability to run through a smaller set of the data or to restart. Feel free to update this doc if you write (or find) examples that do these more advanced things.

Note that the simple pull request _does_ have test coverage. I initially tested it with sqlite and then changed it over to use a MySQL database in test, just to be sure it would work perfectly with our production database.

## 2. Land the transition

Have it reviewed and then land it on main. That way, the code is available to be run via the chatops.

## 3. Create a "production change"-style pull request

This PR documents how we intend to make the change, monitor and test it, plus what we'll do if things go wrong. Here's the PR:

https://github.com/github/osslicensecompliance/pull/348

The body of that PR is based on [this template](https://github.com/github/github/blob/master/pcrs/TEMPLATE.md), though feel free to slim that down as needed.

The only file changed in the PR is [the transition log](https://github.com/github/osslicensecompliance/blob/main/docs/transition-log.md), which documents the who/what/when of the transition.

## 4. Run the transition

[Follow the instructions on The Hub](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/#running-a-transition). Generally speaking, you're going to run a chatop like this:

`.transitions run <PR created in step 3> * <transition name from step 1> other args as needed`

## 5. Merge the production change PR

Go ahead and merge that PR from step 3, just to get the transition log update in.

## 6. Clean up if needed/desired

Some transitions are just "run once and we're done". Feel free to delete the code if it's no longer useful. We can always get it back!

That first transition was [deleted in this PR](https://github.com/github/osslicensecompliance/pull/350).

## 7. Celebrate!

We need to be very careful in rolling out transitions, so it's worth a quick "Huzzah!" when you're all done with one.
