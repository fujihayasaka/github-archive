import crypto from "crypto";
import fs from "fs";
import os from "os";
import path from "path";
import sshpk from "sshpk";

import * as core from "@actions/core";
import { bundleToJSON } from "@sigstore/bundle";
import {
  Artifact,
  Bundle,
  DSSEBundleBuilder,
  RekorWitness,
  Signature,
  Signer,
} from "@sigstore/sign";

const DEFAULT_TIMEOUT = 10000;
const DEFAULT_RETRIES = 3;
const REKOR_URL = "https://rekor.sigstore.dev";
const ATTESTATION_FILE_NAME = "attestation.json";

export type RunInputs = {
  subjectPath: string;
  packageName: string;
  packageVersion: string;
  privateKey: string;
};

// Calculate the digest of the file at the given path
const digestFile = async (
  algorithm: string,
  filePath: string
): Promise<string> => {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash(algorithm).setEncoding("hex");
    fs.createReadStream(filePath)
      .once("error", reject)
      .pipe(hash)
      .once("finish", () => resolve(hash.read()));
  });
};

type StatementOpts = {
  name: string;
  version: string;
  digest: string;
};

// Generate the npm publish statement for the given package
const generateStatement = (opts: StatementOpts): string => {
  const statement = {
    _type: "https://in-toto.io/Statement/v0.1",
    subject: [
      {
        name: `pkg:npm/${encodeURIComponent(opts.name)}@${opts.version}`,
        digest: {
          sha512: opts.digest,
        },
      },
    ],
    predicateType:
      "https://github.com/npm/attestation/tree/main/specs/publish/v0.1",
    predicate: {
      name: opts.name,
      version: opts.version,
      registry: "https://registry.npmjs.org",
    },
  };
  return JSON.stringify(statement);
};

// Instantiates a Signer using the given private key
const makeSigner = (key: string): Signer => {
  const k = Buffer.from(key, "base64").toString("utf-8");
  const privateKey = crypto.createPrivateKey(k);
  const publicKey = crypto.createPublicKey(k);
  const fingerprint = sshpk
    .parsePrivateKey(k, "pem")
    .fingerprint("sha256")
    .toString("base64");

  return {
    sign: async (payload: Buffer): Promise<Signature> => {
      const signature = crypto.sign(undefined, payload, privateKey);
      return {
        signature: signature,
        key: {
          $case: "publicKey",
          hint: fingerprint,
          publicKey: publicKey
            .export({ type: "spki", format: "pem" })
            .toString("base64"),
        },
      };
    },
  };
};

// Returns a new DSSEBundleBuilder instance with the given key
const initBundleBuilder = (key: string) => {
  const signer: Signer = makeSigner(key);

  const witnesses = [
    new RekorWitness({
      rekorBaseURL: REKOR_URL,
      entryType: "intoto",
      fetchOnConflict: true,
      timeout: DEFAULT_TIMEOUT,
      retry: DEFAULT_RETRIES,
    }),
  ];

  return new DSSEBundleBuilder({ signer, witnesses, singleCertificate: false });
};

// Returns the path to a new temporary directory for storing the attestation
const tempDir = (): string => {
  const basePath = process.env["RUNNER_TEMP"] || process.env["TMPDIR"];
  return fs.mkdtempSync(path.join(basePath!, path.sep));
};

export const run = async (inputs: RunInputs): Promise<Bundle> => {
  const digest = await digestFile("sha512", inputs.subjectPath);

  const stmt = generateStatement({
    name: inputs.packageName,
    version: inputs.packageVersion,
    digest: digest,
  });

  const artifact: Artifact = {
    type: "application/vnd.in-toto+json",
    data: Buffer.from(stmt),
  };

  const bundle = await initBundleBuilder(inputs.privateKey).create(artifact);

  const outputPath = path.join(tempDir(), ATTESTATION_FILE_NAME);
  core.setOutput("bundle-path", outputPath);

  fs.writeFileSync(outputPath, JSON.stringify(bundleToJSON(bundle)) + os.EOL, {
    encoding: "utf-8",
  });

  return bundle;
};
