import { useLoaderData, Link as RouterLink, Navigate } from "react-router-dom";
import { findAnything } from "../../api";
import { FileDirectorySymlinkIcon, MarkGithubIcon, PersonIcon } from "@primer/octicons-react";
import { DataTable, Table } from "@primer/react/drafts";
import { PageLayout } from "@primer/react";

export async function loader({ request, params }) {
  const stamp = params.stamp;
  const url = new URL(request.url);
  const q = url.searchParams.get("q");
  const { repositories, filesets, owners } = await findAnything(stamp, { q: q });
  return { repositories, filesets, owners, stamp, q };
}

export default function SearchResults() {
  const { repositories, filesets, owners, stamp, q } = useLoaderData();

  if (repositories.length === 1 && filesets.length === 0 && owners.length === 0) {
    return <Navigate replace to={`/stamps/${stamp}/repos/${repositories[0].repo_id}`} />;
  } else if (filesets.length === 1 && repositories.length === 0 && owners.length === 0) {
    return <Navigate replace to={`/stamps/${stamp}/filesets/${filesets[0].repo_id}`} />;
  } else if (owners.length === 1 && repositories.length === 0 && filesets.length === 0) {
    return <Navigate replace to={`/stamps/${stamp}/users/${owners[0].login}`} />;
  }

  const repos = repositories.map((r) => {
    return {
      id: r.repo_id,
      nwo: <RouterLink to={`/stamps/${stamp}/repos/${r.repo_id}`}>{r.repo_nwo}</RouterLink>,
      deleted_at: r.deleted_at,
      type: "Repository",
      icon: <MarkGithubIcon size={16} />,
    };
  });

  const fs = filesets.map((f) => {
    return {
      id: f.repo_id,
      nwo: <RouterLink to={`/stamps/${stamp}/filesets/${f.repo_id}`}>{f.fileset}</RouterLink>,
      deleted_at: f.deleted_at,
      type: "Fileset",
      icon: <FileDirectorySymlinkIcon size={16} />,
    };
  });

  const users = owners.map((o) => {
    return {
      id: o.owner_id,
      nwo: <RouterLink to={`/stamps/${stamp}/users/${o.login}`}>{o.login}</RouterLink>,
      type: "User",
      icon: <PersonIcon size={16} />,
    };
  });

  const data = repos.concat(fs).concat(users);

  return (
    <PageLayout>
      <PageLayout.Header>
        Results for <code>{q}</code>
      </PageLayout.Header>
      <PageLayout.Content>
        <Table.Container>
          <DataTable
            data={data}
            columns={[
              { header: "", field: "icon", width: "40px" },
              { header: "", field: "type", maxWidth: "120px" },
              { header: "Id", field: "id", maxWidth: "100px" },
              { header: "Name", field: "nwo" },
              { header: "Deleted", field: "deleted_at" },
            ]}
          />
        </Table.Container>
      </PageLayout.Content>
    </PageLayout>
  );
}
