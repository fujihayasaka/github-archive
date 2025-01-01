/**
 * @generated SignedSource<<3a41e9aa7529bb7caf511c06d55c5275>>
 * @relayHash b09447a2509e642d1876e9d2b8e12776
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b09447a2509e642d1876e9d2b8e12776

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type TimelineItemsTestQuery$variables = Record<PropertyKey, never>;
export type TimelineItemsTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly timelineItems: {
        readonly " $fragmentSpreads": FragmentRefs<"TimelineItemsPaginated">;
      };
    } | null | undefined;
  } | null | undefined;
  readonly viewer: {
    readonly login: string;
  };
};
export type TimelineItemsTestQuery = {
  response: TimelineItemsTestQuery$data;
  variables: TimelineItemsTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 33
  }
],
v2 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 10
  }
],
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v4 = [
  (v3/*: any*/)
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = [
  (v5/*: any*/),
  (v3/*: any*/),
  (v7/*: any*/)
],
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v16 = [
  (v7/*: any*/)
],
v17 = {
  "kind": "InlineFragment",
  "selections": (v16/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v18 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v19 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "size",
      "value": 64
    }
  ],
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": "avatarUrl(size:64)"
},
v20 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v3/*: any*/),
    (v7/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/)
  ],
  "storageKey": null
},
v21 = [
  (v5/*: any*/),
  (v17/*: any*/)
],
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v24 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "commonName",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "emailAddress",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "organization",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "organizationUnit",
    "storageKey": null
  }
],
v25 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v8/*: any*/),
  "storageKey": null
},
v26 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "enableDuplicate",
      "value": true
    }
  ],
  "kind": "ScalarField",
  "name": "stateReason",
  "storageKey": "stateReason(enableDuplicate:true)"
},
v28 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    (v13/*: any*/),
    (v14/*: any*/),
    (v25/*: any*/)
  ],
  "storageKey": null
},
v29 = {
  "kind": "InlineFragment",
  "selections": [
    (v7/*: any*/),
    (v26/*: any*/),
    (v10/*: any*/),
    (v9/*: any*/),
    (v27/*: any*/),
    (v28/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v30 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v33 = {
  "kind": "InlineFragment",
  "selections": [
    (v7/*: any*/),
    (v30/*: any*/),
    (v10/*: any*/),
    (v9/*: any*/),
    (v23/*: any*/),
    (v31/*: any*/),
    (v32/*: any*/),
    (v28/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v34 = [
  (v11/*: any*/),
  (v20/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v7/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v13/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "color",
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "description",
        "storageKey": null
      }
    ],
    "storageKey": null
  },
  (v6/*: any*/)
],
v35 = [
  (v7/*: any*/),
  (v3/*: any*/)
],
v36 = [
  (v11/*: any*/),
  (v20/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "assignee",
    "plural": false,
    "selections": [
      (v5/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": (v35/*: any*/),
        "type": "User",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v35/*: any*/),
        "type": "Bot",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v35/*: any*/),
        "type": "Mannequin",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v35/*: any*/),
        "type": "Organization",
        "abstractKey": null
      },
      (v17/*: any*/)
    ],
    "storageKey": null
  },
  (v6/*: any*/)
],
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v37/*: any*/),
    (v10/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v39 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/),
    (v3/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    (v10/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v42 = [
  (v11/*: any*/),
  (v6/*: any*/),
  (v39/*: any*/)
],
v43 = {
  "kind": "InlineFragment",
  "selections": [
    (v29/*: any*/),
    (v33/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v44 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    (v25/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v45 = [
  (v6/*: any*/),
  (v11/*: any*/),
  (v39/*: any*/)
],
v46 = [
  (v3/*: any*/),
  (v7/*: any*/)
],
v47 = [
  (v6/*: any*/),
  (v11/*: any*/),
  (v39/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v10/*: any*/),
      (v7/*: any*/)
    ],
    "storageKey": null
  }
],
v48 = [
  (v6/*: any*/),
  (v39/*: any*/),
  (v11/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v5/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v37/*: any*/),
          (v10/*: any*/),
          (v9/*: any*/),
          (v23/*: any*/),
          (v31/*: any*/),
          (v32/*: any*/),
          (v44/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v17/*: any*/)
    ],
    "storageKey": null
  }
],
v49 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v26/*: any*/),
        (v10/*: any*/),
        (v27/*: any*/),
        (v28/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v30/*: any*/),
        (v10/*: any*/),
        (v23/*: any*/),
        (v31/*: any*/),
        (v32/*: any*/),
        (v28/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v51 = [
  (v43/*: any*/)
],
v52 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v53 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v54 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v55 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v56 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v57 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v61 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v62 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v63 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v64 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v65 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v66 = {
  "enumValues": [
    "COMPLETED",
    "DUPLICATE",
    "NOT_PLANNED",
    "REOPENED"
  ],
  "nullable": true,
  "plural": false,
  "type": "IssueStateReason"
},
v67 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v68 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v69 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v70 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v71 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "TimelineItemsTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": (v2/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "TimelineItemsPaginated"
                  }
                ],
                "storageKey": "timelineItems(last:10)"
              }
            ],
            "storageKey": "issue(number:33)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": (v4/*: any*/),
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "TimelineItemsTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": (v2/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "IssueTimelineItemsEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v5/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerDidAuthor",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Issue",
                                "kind": "LinkedField",
                                "name": "issue",
                                "plural": false,
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "author",
                                    "plural": false,
                                    "selections": (v8/*: any*/),
                                    "storageKey": null
                                  },
                                  (v7/*: any*/),
                                  (v9/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "locked",
                                    "storageKey": null
                                  },
                                  (v6/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v7/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "body",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": [
                                  {
                                    "kind": "Literal",
                                    "name": "unfurlReferences",
                                    "value": true
                                  }
                                ],
                                "kind": "ScalarField",
                                "name": "bodyHTML",
                                "storageKey": "bodyHTML(unfurlReferences:true)"
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "bodyVersion",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUpdate",
                                "storageKey": null
                              },
                              (v10/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "authorAssociation",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanDelete",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanMinimize",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanReport",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanReportToMaintainer",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanBlockFromOrg",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUnblockFromOrg",
                                "storageKey": null
                              },
                              {
                                "alias": "isHidden",
                                "args": null,
                                "kind": "ScalarField",
                                "name": "isMinimized",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "minimizedReason",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "showSpammyBadge",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "createdViaEmail",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Sponsorship",
                                "kind": "LinkedField",
                                "name": "authorToRepoOwnerSponsorship",
                                "plural": false,
                                "selections": [
                                  (v11/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "isActive",
                                    "storageKey": null
                                  },
                                  (v7/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "author",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  (v7/*: any*/),
                                  (v3/*: any*/),
                                  (v12/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "repository",
                                "plural": false,
                                "selections": [
                                  (v7/*: any*/),
                                  (v13/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "owner",
                                    "plural": false,
                                    "selections": [
                                      (v5/*: any*/),
                                      (v7/*: any*/),
                                      (v3/*: any*/),
                                      (v10/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v14/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slashCommandsEnabled",
                                    "storageKey": null
                                  },
                                  (v15/*: any*/),
                                  (v6/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "viewerCanReadUserContentEdits",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "lastEditedAt",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "UserContentEdit",
                                    "kind": "LinkedField",
                                    "name": "lastUserContentEdit",
                                    "plural": false,
                                    "selections": [
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": null,
                                        "kind": "LinkedField",
                                        "name": "editor",
                                        "plural": false,
                                        "selections": [
                                          (v5/*: any*/),
                                          (v10/*: any*/),
                                          (v3/*: any*/),
                                          (v7/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v7/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "type": "Comment",
                                "abstractKey": "__isComment"
                              },
                              {
                                "kind": "ClientExtension",
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "pendingMinimizeReason",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "pendingBlock",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "pendingUnblock",
                                    "storageKey": null
                                  }
                                ]
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "ReactionGroup",
                                    "kind": "LinkedField",
                                    "name": "reactionGroups",
                                    "plural": true,
                                    "selections": [
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "content",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "viewerHasReacted",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": [
                                          {
                                            "kind": "Literal",
                                            "name": "first",
                                            "value": 5
                                          }
                                        ],
                                        "concreteType": "ReactorConnection",
                                        "kind": "LinkedField",
                                        "name": "reactors",
                                        "plural": false,
                                        "selections": [
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "totalCount",
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": null,
                                            "kind": "LinkedField",
                                            "name": "nodes",
                                            "plural": true,
                                            "selections": [
                                              (v5/*: any*/),
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v4/*: any*/),
                                                "type": "User",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v4/*: any*/),
                                                "type": "Bot",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v4/*: any*/),
                                                "type": "Organization",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v4/*: any*/),
                                                "type": "Mannequin",
                                                "abstractKey": null
                                              },
                                              (v17/*: any*/)
                                            ],
                                            "storageKey": null
                                          }
                                        ],
                                        "storageKey": "reactors(first:5)"
                                      }
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "type": "Reactable",
                                "abstractKey": "__isReactable"
                              }
                            ],
                            "type": "IssueComment",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v20/*: any*/),
                              (v6/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "willCloseSubject",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": (v21/*: any*/),
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Commit",
                                "kind": "LinkedField",
                                "name": "commit",
                                "plural": false,
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "message",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "messageHeadlineHTML",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "messageBodyHTML",
                                    "storageKey": null
                                  },
                                  (v10/*: any*/),
                                  (v22/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "signature",
                                    "plural": false,
                                    "selections": [
                                      (v5/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": "User",
                                        "kind": "LinkedField",
                                        "name": "signer",
                                        "plural": false,
                                        "selections": [
                                          (v3/*: any*/),
                                          (v12/*: any*/),
                                          (v7/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v23/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "wasSignedByGitHub",
                                        "storageKey": null
                                      },
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "CertificateAttributes",
                                            "kind": "LinkedField",
                                            "name": "issuer",
                                            "plural": false,
                                            "selections": (v24/*: any*/),
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "CertificateAttributes",
                                            "kind": "LinkedField",
                                            "name": "subject",
                                            "plural": false,
                                            "selections": (v24/*: any*/),
                                            "storageKey": null
                                          }
                                        ],
                                        "type": "SmimeSignature",
                                        "abstractKey": null
                                      },
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "keyId",
                                            "storageKey": null
                                          }
                                        ],
                                        "type": "GpgSignature",
                                        "abstractKey": null
                                      },
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "keyFingerprint",
                                            "storageKey": null
                                          }
                                        ],
                                        "type": "SshSignature",
                                        "abstractKey": null
                                      }
                                    ],
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "verificationStatus",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "hasSignature",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": [
                                      (v13/*: any*/),
                                      (v25/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "defaultBranch",
                                        "storageKey": null
                                      },
                                      (v7/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v7/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "ReferencedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v20/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "source",
                                "plural": false,
                                "selections": (v21/*: any*/),
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "willCloseTarget",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "referencedAt",
                                "storageKey": null
                              },
                              (v6/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "target",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": "Repository",
                                        "kind": "LinkedField",
                                        "name": "repository",
                                        "plural": false,
                                        "selections": (v16/*: any*/),
                                        "storageKey": null
                                      }
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  (v17/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "alias": "innerSource",
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "source",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  {
                                    "kind": "TypeDiscriminator",
                                    "abstractKey": "__isReferencedSubject"
                                  },
                                  (v29/*: any*/),
                                  (v33/*: any*/),
                                  (v17/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "CrossReferencedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v20/*: any*/),
                              (v11/*: any*/),
                              (v6/*: any*/)
                            ],
                            "type": "MentionedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v34/*: any*/),
                            "type": "LabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v34/*: any*/),
                            "type": "UnlabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v36/*: any*/),
                            "type": "AssignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v36/*: any*/),
                            "type": "UnassignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v20/*: any*/),
                              (v6/*: any*/),
                              (v38/*: any*/)
                            ],
                            "type": "AddedToProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v20/*: any*/),
                              (v38/*: any*/)
                            ],
                            "type": "RemovedFromProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v39/*: any*/),
                              (v40/*: any*/),
                              (v41/*: any*/),
                              (v6/*: any*/)
                            ],
                            "type": "AddedToProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v6/*: any*/),
                              (v39/*: any*/),
                              (v40/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "previousProjectColumnName",
                                "storageKey": null
                              },
                              (v41/*: any*/)
                            ],
                            "type": "MovedColumnsInProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v6/*: any*/),
                              (v39/*: any*/),
                              (v40/*: any*/),
                              (v41/*: any*/)
                            ],
                            "type": "RemovedFromProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v42/*: any*/),
                            "type": "SubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v42/*: any*/),
                            "type": "UnsubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v11/*: any*/),
                              (v27/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "duplicateOf",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  (v43/*: any*/),
                                  (v17/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "closingProjectItemStatus",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "closer",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v10/*: any*/),
                                      (v37/*: any*/)
                                    ],
                                    "type": "ProjectV2",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v10/*: any*/),
                                      (v9/*: any*/),
                                      (v44/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v10/*: any*/),
                                      (v22/*: any*/),
                                      (v44/*: any*/)
                                    ],
                                    "type": "Commit",
                                    "abstractKey": null
                                  },
                                  (v17/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v39/*: any*/)
                            ],
                            "type": "ClosedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v45/*: any*/),
                            "type": "ReopenedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "lockReason",
                                "storageKey": null
                              },
                              (v39/*: any*/)
                            ],
                            "type": "LockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v45/*: any*/),
                            "type": "UnlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v45/*: any*/),
                            "type": "PinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v45/*: any*/),
                            "type": "UnpinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v11/*: any*/),
                              (v39/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "currentTitle",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "previousTitle",
                                "storageKey": null
                              }
                            ],
                            "type": "RenamedTitleEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v11/*: any*/),
                              (v39/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "deletedCommentAuthor",
                                "plural": false,
                                "selections": (v8/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "CommentDeletedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "blockDuration",
                                "storageKey": null
                              },
                              (v39/*: any*/),
                              {
                                "alias": "blockedUser",
                                "args": null,
                                "concreteType": "User",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": (v46/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "UserBlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v47/*: any*/),
                            "type": "MilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v47/*: any*/),
                            "type": "DemilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v48/*: any*/),
                            "type": "ConnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v39/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "fromRepository",
                                "plural": false,
                                "selections": [
                                  (v15/*: any*/),
                                  (v10/*: any*/),
                                  (v7/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "TransferredEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v39/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Project",
                                "kind": "LinkedField",
                                "name": "project",
                                "plural": false,
                                "selections": [
                                  (v10/*: any*/),
                                  (v13/*: any*/),
                                  (v7/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "ConvertedNoteToIssueEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v48/*: any*/),
                            "type": "DisconnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v39/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "canonical",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v7/*: any*/),
                                      (v9/*: any*/),
                                      (v49/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v9/*: any*/),
                                      (v7/*: any*/),
                                      (v49/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v17/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v50/*: any*/),
                              (v6/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUndo",
                                "storageKey": null
                              },
                              (v7/*: any*/),
                              {
                                "kind": "ClientExtension",
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "pendingUndo",
                                    "storageKey": null
                                  }
                                ]
                              }
                            ],
                            "type": "MarkedAsDuplicateEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v39/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "canonical",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v51/*: any*/),
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v51/*: any*/),
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v17/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v50/*: any*/),
                              (v6/*: any*/)
                            ],
                            "type": "UnmarkedAsDuplicateEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v39/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Discussion",
                                "kind": "LinkedField",
                                "name": "discussion",
                                "plural": false,
                                "selections": [
                                  (v10/*: any*/),
                                  (v9/*: any*/),
                                  (v7/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "ConvertedToDiscussionEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v39/*: any*/),
                              (v38/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "previousStatus",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "status",
                                "storageKey": null
                              }
                            ],
                            "type": "ProjectV2ItemStatusChangedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v11/*: any*/),
                              (v39/*: any*/),
                              (v6/*: any*/)
                            ],
                            "type": "ConvertedFromDraftEvent",
                            "abstractKey": null
                          },
                          (v17/*: any*/),
                          {
                            "kind": "ClientExtension",
                            "selections": [
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "__id",
                                "storageKey": null
                              }
                            ]
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "timelineItems(last:10)"
              },
              (v7/*: any*/)
            ],
            "storageKey": "issue(number:33)"
          },
          (v7/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": (v46/*: any*/),
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "b09447a2509e642d1876e9d2b8e12776",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": (v52/*: any*/),
        "repository.id": (v53/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.id": (v53/*: any*/),
        "repository.issue.timelineItems": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueTimelineItemsConnection"
        },
        "repository.issue.timelineItems.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTimelineItemsEdge"
        },
        "repository.issue.timelineItems.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueTimelineItems"
        },
        "repository.issue.timelineItems.edges.node.__id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.__isComment": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.__isReactable": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.actor": (v55/*: any*/),
        "repository.issue.timelineItems.edges.node.actor.__isActor": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.actor.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.actor.avatarUrl": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.actor.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.actor.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "repository.issue.timelineItems.edges.node.assignee.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.assignee.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.assignee.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.assignee.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.author": (v55/*: any*/),
        "repository.issue.timelineItems.edges.node.author.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.author.avatarUrl": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.author.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.author.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.authorAssociation": {
          "enumValues": [
            "COLLABORATOR",
            "CONTRIBUTOR",
            "FIRST_TIMER",
            "FIRST_TIME_CONTRIBUTOR",
            "MANNEQUIN",
            "MEMBER",
            "NONE",
            "OWNER"
          ],
          "nullable": false,
          "plural": false,
          "type": "CommentAuthorAssociation"
        },
        "repository.issue.timelineItems.edges.node.authorToRepoOwnerSponsorship": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Sponsorship"
        },
        "repository.issue.timelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v57/*: any*/),
        "repository.issue.timelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.blockDuration": {
          "enumValues": [
            "ONE_DAY",
            "ONE_MONTH",
            "ONE_WEEK",
            "PERMANENT",
            "THREE_DAYS"
          ],
          "nullable": false,
          "plural": false,
          "type": "UserBlockDuration"
        },
        "repository.issue.timelineItems.edges.node.blockedUser": (v59/*: any*/),
        "repository.issue.timelineItems.edges.node.blockedUser.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.blockedUser.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.body": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.bodyHTML": (v60/*: any*/),
        "repository.issue.timelineItems.edges.node.bodyVersion": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical": (v61/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.__isReferencedSubject": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.isDraft": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.isInMergeQueue": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.issueTitleHTML": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.pullTitleHTML": (v60/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.isPrivate": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.state": (v65/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.stateReason": (v66/*: any*/),
        "repository.issue.timelineItems.edges.node.canonical.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "repository.issue.timelineItems.edges.node.closer.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.abbreviatedOid": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.title": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.closer.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.closingProjectItemStatus": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "repository.issue.timelineItems.edges.node.commit.abbreviatedOid": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.hasSignature": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.message": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.messageBodyHTML": (v60/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.messageHeadlineHTML": (v60/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.defaultBranch": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "repository.issue.timelineItems.edges.node.commit.signature.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.issuer": (v68/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.issuer.commonName": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.issuer.emailAddress": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.issuer.organization": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.issuer.organizationUnit": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.keyFingerprint": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.keyId": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.signer": (v59/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.signer.avatarUrl": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.signer.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.signer.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.state": {
          "enumValues": [
            "BAD_CERT",
            "BAD_EMAIL",
            "EXPIRED_KEY",
            "GPGVERIFY_ERROR",
            "GPGVERIFY_UNAVAILABLE",
            "INVALID",
            "MALFORMED_SIG",
            "NOT_SIGNING_KEY",
            "NO_USER",
            "OCSP_ERROR",
            "OCSP_PENDING",
            "OCSP_REVOKED",
            "UNKNOWN_KEY",
            "UNKNOWN_SIG_TYPE",
            "UNSIGNED",
            "UNVERIFIED_EMAIL",
            "VALID"
          ],
          "nullable": false,
          "plural": false,
          "type": "GitSignatureState"
        },
        "repository.issue.timelineItems.edges.node.commit.signature.subject": (v68/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.subject.commonName": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.subject.emailAddress": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.subject.organization": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.subject.organizationUnit": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.signature.wasSignedByGitHub": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.commit.verificationStatus": {
          "enumValues": [
            "PARTIALLY_VERIFIED",
            "UNSIGNED",
            "UNVERIFIED",
            "VERIFIED"
          ],
          "nullable": true,
          "plural": false,
          "type": "CommitVerificationStatus"
        },
        "repository.issue.timelineItems.edges.node.createdAt": (v57/*: any*/),
        "repository.issue.timelineItems.edges.node.createdViaEmail": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.currentTitle": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.databaseId": (v69/*: any*/),
        "repository.issue.timelineItems.edges.node.deletedCommentAuthor": (v55/*: any*/),
        "repository.issue.timelineItems.edges.node.deletedCommentAuthor.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.deletedCommentAuthor.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.deletedCommentAuthor.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "repository.issue.timelineItems.edges.node.discussion.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.discussion.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.discussion.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf": (v61/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.__isReferencedSubject": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.isDraft": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.isInMergeQueue": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.issueTitleHTML": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.pullTitleHTML": (v60/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.isPrivate": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.state": (v65/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.stateReason": (v66/*: any*/),
        "repository.issue.timelineItems.edges.node.duplicateOf.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.fromRepository": (v52/*: any*/),
        "repository.issue.timelineItems.edges.node.fromRepository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.fromRepository.nameWithOwner": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.fromRepository.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource": (v70/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.__isReferencedSubject": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.isDraft": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.isInMergeQueue": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.issueTitleHTML": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.pullTitleHTML": (v60/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.isPrivate": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.state": (v65/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.stateReason": (v66/*: any*/),
        "repository.issue.timelineItems.edges.node.innerSource.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.isCanonicalOfClosedDuplicate": (v71/*: any*/),
        "repository.issue.timelineItems.edges.node.isHidden": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.timelineItems.edges.node.issue.author": (v55/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.author.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.author.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.author.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.databaseId": (v69/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.locked": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.issue.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "repository.issue.timelineItems.edges.node.label.color": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.label.description": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.label.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.label.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.label.nameHTML": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.lastEditedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "repository.issue.timelineItems.edges.node.lastUserContentEdit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "UserContentEdit"
        },
        "repository.issue.timelineItems.edges.node.lastUserContentEdit.editor": (v55/*: any*/),
        "repository.issue.timelineItems.edges.node.lastUserContentEdit.editor.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.lastUserContentEdit.editor.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.lastUserContentEdit.editor.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.lastUserContentEdit.editor.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.lastUserContentEdit.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.lockReason": {
          "enumValues": [
            "OFF_TOPIC",
            "RESOLVED",
            "SPAM",
            "TOO_HEATED"
          ],
          "nullable": true,
          "plural": false,
          "type": "LockReason"
        },
        "repository.issue.timelineItems.edges.node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "repository.issue.timelineItems.edges.node.milestone.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.milestone.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.milestoneTitle": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.minimizedReason": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.pendingBlock": (v71/*: any*/),
        "repository.issue.timelineItems.edges.node.pendingMinimizeReason": (v67/*: any*/),
        "repository.issue.timelineItems.edges.node.pendingUnblock": (v71/*: any*/),
        "repository.issue.timelineItems.edges.node.pendingUndo": (v71/*: any*/),
        "repository.issue.timelineItems.edges.node.previousProjectColumnName": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.previousStatus": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.previousTitle": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2"
        },
        "repository.issue.timelineItems.edges.node.project.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.project.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.project.title": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.project.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.projectColumnName": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.reactionGroups": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ReactionGroup"
        },
        "repository.issue.timelineItems.edges.node.reactionGroups.content": {
          "enumValues": [
            "CONFUSED",
            "EYES",
            "HEART",
            "HOORAY",
            "LAUGH",
            "ROCKET",
            "THUMBS_DOWN",
            "THUMBS_UP"
          ],
          "nullable": false,
          "plural": false,
          "type": "ReactionContent"
        },
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ReactorConnection"
        },
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Reactor"
        },
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors.nodes.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors.nodes.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.reactionGroups.reactors.totalCount": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.reactionGroups.viewerHasReacted": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.referencedAt": (v57/*: any*/),
        "repository.issue.timelineItems.edges.node.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.databaseId": (v69/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.isPrivate": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.nameWithOwner": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.owner.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.repository.slashCommandsEnabled": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.showSpammyBadge": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.source": (v70/*: any*/),
        "repository.issue.timelineItems.edges.node.source.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.source.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.source.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.stateReason": (v66/*: any*/),
        "repository.issue.timelineItems.edges.node.status": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject": (v70/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.isDraft": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.isInMergeQueue": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.number": (v62/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository.name": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository.owner": (v64/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository.owner.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository.owner.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.repository.owner.login": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.state": (v65/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.title": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.subject.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.target": (v70/*: any*/),
        "repository.issue.timelineItems.edges.node.target.__isNode": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.target.__typename": (v54/*: any*/),
        "repository.issue.timelineItems.edges.node.target.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.target.repository": (v63/*: any*/),
        "repository.issue.timelineItems.edges.node.target.repository.id": (v53/*: any*/),
        "repository.issue.timelineItems.edges.node.url": (v56/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanBlockFromOrg": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanDelete": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanMinimize": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanReadUserContentEdits": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanReport": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanReportToMaintainer": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanUnblockFromOrg": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanUndo": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerCanUpdate": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.viewerDidAuthor": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.willCloseSubject": (v58/*: any*/),
        "repository.issue.timelineItems.edges.node.willCloseTarget": (v58/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.id": (v53/*: any*/),
        "viewer.login": (v54/*: any*/)
      }
    },
    "name": "TimelineItemsTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "762852d7f7787525bdb9cbe52c528f33";

export default node;
