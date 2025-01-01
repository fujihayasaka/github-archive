function runner(spawnSync, file, ...outerArgs) {
    return function (...args) {
        const {
            stdout,
            stderr,
            status
        } = spawnSync(file, [...outerArgs, ...args], {
            encoding: 'utf-8',
            cwd: process.env.GITHUB_WORKSPACE
        })

        if (status !== 0) {
            throw new Error(stderr);
        }

        return stdout.trim();
    }
}

function checkbox(comment, tag) {
    const checked = `[x] <!-- ${tag} -->`;
    if (comment.toLowerCase().includes(checked)) {
        return checked;
    }
    return `[ ] <!-- ${tag} -->`;
}

module.exports = async ({modules, comment}) => {
    const {core, spawnSync, io} = modules;

    const modified = function (gitPath) {
        const gitDiff = runner(spawnSync, gitPath, 'diff', 'HEAD^..HEAD', '--name-only');
        return function (...args) {
            const changed = gitDiff(...args).length > 0
            if (changed) {
                core.info(`Detected changes in one of: ${args.join(", ")}`);
            }
            return changed;
        }
    }(await io.which('git', true));

    const anyChanges = (...args) => modified('--', ...args);
    const addedDeletedOrRenamed = (...args) => modified('--diff-filter', 'ADR', '--', ...args);

    const items = [];

    if (anyChanges('turboscan-client.gemspec', 'ruby/lib/**', 'ruby/spec/fixtures/vcr_cassettes/**/*.yml')) {
        items.push(`- ${checkbox(comment.body, 'gem')} ` + "Gem appears to have changed. Remember to re-vendor the Turboscan client gem into `github/github`: [instructions](https://github.com/github/turboscan/blob/main/README.md#turboscan-client-gem).");
    }
    if (anyChanges('ruby/lib/turboscan/proto/*.rb')) {
        items.push(`- ${checkbox(comment.body, 'sha1-sync')} ` + "If you have modified a Twirp interface, please follow these steps: [When it is next vendored into `github/github`](https://github.com/github/turboscan/blob/main/README.md#turboscan-client-gem), make sure to run `.ghe sha1-sync master turboscan` in [#dsp-code-scanning-ops](https://github.slack.com/archives/C012V1VS2N4). Hubot will open a PR in the `enterprise2` repo to bump the version automatically. Once you receive reviewer approval and pass all `Required` checks, merge the PR. If a `Required` check fails, you may need to re-run it many times. You may also need to ping [#ghes-core-infrastructure](https://github.slack.com/archives/C03H0U7G109) for review.");
    }
    if (anyChanges('ts/mysql/upgrades/transitions.go')) {
        items.push(`- ${checkbox(comment.body, 'transition')} ` + "You appear to have added a transition. Please add it to script/db-migrate.");
    }
    if (anyChanges('ruby/lib/turboscan/proto/results_pb.rb')) {
        items.push(`- ${checkbox(comment.body, 'twirp')} ` + "If you have added a Twirp endpoint, please add a test for the Ruby client gem.");
    }
    if (anyChanges('schemas/*.sql')) {
        items.push(`- ${checkbox(comment.body, 'airflow')} ` + "If you have changed the database schema, please make any necessary changes to Airflow.");
    }
    if (anyChanges('ts/proto/results.pb.go')) {
        items.push(`- ${checkbox(comment.body, 'proto')} ` + "If you have changed the Result struct, please make sure you re-vendor the Alert Hydro schema if necessary.");
    }
    if (addedDeletedOrRenamed('schemas/*.sql')) {
        items.push(`- ${checkbox(comment.body, 'vitess')} ` + "If you have changed the database schema, please update *.vschema.json.");
    }

    if (items.length === 0) {
        core.info(`No todo items detected.`);
        return comment.body;
    }

    return `PR Checklist:\n` + items.join(`\n`);
}
