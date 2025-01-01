## Dependency Graph & WSL2 & Debian 10

First, make sure you've set up doctcom following these [instructions](https://thehub.github.com/engineering/development-and-ops/dotcom/wsl/)

Run `scripts/bootstrap` if you see warnings like 'failed post install', 'Error: Invalid usage: `brew services` is supported only on macOS!' don't worry about it. If you followed the dotcom instructions, opening a new terminal will already make sure all the necessary services are running.

Make sure `eval "$(rbenv init -)"` is in your `.bashrc` and `.profile`.
<details>
  <summary>Why this step exists</summary>

  I got an error that looked like this:  `earthsmoke-1.2.5 requires ruby version ~> 2.3, which is incompatible with the current version, ruby 3.0.0p0`

  I checked `rbenv versions` to make sure the right version was being used. It was:
  ```
tevoinea@DESKTOP-33LVIH6:~/github/dependency-graph-api$ rbenv versions
  system
* 2.7.1 (set by /home/tevoinea/github/dependency-graph-api/.ruby-version)
  ```

  I checked `rbenv doctor` (see 'When in doubt') and all the checks were ok.

  It's also possible the `system` version of ruby is taking precendence over the rbenv one in your `$PATH`.

  Doing `source ~/.bash_profile` inside `.profile` is also a common fix.
</details>

Run `scripts/setup`. If you see errors about missing libs (in my case libffi.so.7), try to find the package (either in debian package repository or ubuntu) to install eg: https://packages.ubuntu.com/focal/libffi7.

Another possibility is that the library is installed by brew but not in your path. You can run this command `find /home/linuxbrew/.linuxbrew/Cellar/ -name "libffi.so*"` replacing libffi.so with your missing library to see if brew has it. You can then copy the file to `/usr/lib/x86_64-linux-gnu/`.
<details>
  <summary>Why this step exists</summary>

  While running `bundle exec rake db:create` I got this error:
  ```
  rake aborted!
LoadError: libffi.so.7: cannot open shared object file: No such file or directory - /home/tevoinea/github/dependency-graph-api/vendor/gems/ruby/2.7.0/gems/ffi-1.13.1/lib/ffi_c.so
  ```

  I tried `bundle pristine` and `bundle package` but that didn't fix the issue.

  I also found this [forum](https://discuss.circleci.com/t/how-to-get-ffi-working-on-ruby-2-7-2-image/37787/2) that pointed me in the right direction
</details>

When in doubt make sure:

1. `brew doctor` is passing
1. [rbenv doctor](https://github.com/rbenv/rbenv-installer#rbenv-doctor) is passing
