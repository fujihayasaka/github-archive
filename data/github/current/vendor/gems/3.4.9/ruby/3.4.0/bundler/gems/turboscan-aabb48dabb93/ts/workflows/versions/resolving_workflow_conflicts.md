# How to resolve conflicts with upstream workflow template changes

If you've made changes to the workflow template in your PR by introducing a new `vXX.codeql.template` file but there were also changes that created a file with the same name on `main` you cannot just merge the two versions but need to create a new, higher version workflow file. One way to do this, is the following.

In the example, we assume that in your branch you've made changes that update the workflow version from v21 to v22 while on `main` two independent workflow upgrades have been made since you branched off it, so the latest workflow version there is v23.

1. On your branch, prepare for the merge by renaming your new workflow file to the version it is going to eventually have, i.e. one higher than what is the latest on `main`.

   ```shell
   > git mv ts/workflows/versions/v22.codeql.template ts/workflows/versions/v24.codeql.template
   > git commit -m "Move new template to avoid conflicts"
   ```

2. Having avoided conflicts in the new workflow file, we can merge main. You might still have conflicts in other files that you would have to resolve as part of this step.

   ```shell
   > git merge origin/main
   ```

3. Now that we've merged in `main` we still have some wrong content:

    - In the new workflow file, `v24.codeql.template`, the newer changes made to the template in `main` are missing.
    - `NextVersion` in `ts/workflows/library.go` might still list the wrong version, unless you had a conflict and resolved it already.
   We'll address these in the following steps.

4. Update the value of `NextVersion` in `ts/workflows/library.go` to the new versions (in the example to `"v24"`)

5. Apply the changes made between the common base version of the template and the latest template on main to the new template file using `git merge-file <current> <base> <other>`.

   ```shell
   > cd ts/workflows/versions
   > git merge-file v24.codeql.template v21.codeql.template v23.codeql.template
   ```

6. Add the changes to the merge commit

   ```shell
   > cd ../../..
   > git add ts/workflows/library.go
   > git add ts/workflows/versions/v24.codeql.template
   > git commit --amend
   ```

You should now be able to push to GitHub and check the PR diff to confirm the changes are as intended.
