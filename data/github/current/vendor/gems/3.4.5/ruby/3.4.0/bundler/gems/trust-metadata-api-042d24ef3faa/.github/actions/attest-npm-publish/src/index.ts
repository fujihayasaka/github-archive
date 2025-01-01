import * as core from "@actions/core";
import { run, RunInputs } from "./main";

const inputs: RunInputs = {
  subjectPath: core.getInput("subject-path"),
  packageName: core.getInput("package-name"),
  packageVersion: core.getInput("package-version"),
  privateKey: core.getInput("private-key"),
};

run(inputs);
