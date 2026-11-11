Production Change Records
-------------------------

For changes to production that don't involve code changes, and therefore do not
have an associated Pull Request, we use Production Change Records, or PCRs.

The process is outlined on [the hub][pcrs].

Specifically, see the [how to create a pcr][how-to] section, but in short, the PCRs will be stored in markdown files with naming scheme `pcrs/YYYY/MM/DD-<title>.md`.
Use the [PCR template][template] to guide the structure of your document.

To create a PCR Pull Request, please use the PR template in `.github/PULL_REQUEST_TEMPLATE/production_change_request.md`.
Once you have a branch with your changes, you can create the pull request by that uses the PCR PR template by forming the the following URL with your branch name:

`https://github.com/github/dependabot-api/compare/main...<branch-name>?quick_pull=1&template=production_change_request.md`

[pcrs]: https://thehub.github.com/epd/engineering/dev-practicals/safe-deployment-practices/production-change-record
[how-to]: https://thehub.github.com/epd/engineering/dev-practicals/safe-deployment-practices/production-change-record/#how-to-create-a-pcr
[template]: https://github.com/github/dependabot-api/blob/main/pcrs/TEMPLATE.md
