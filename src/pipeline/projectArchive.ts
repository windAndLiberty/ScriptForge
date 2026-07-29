import type { StoredProject } from "../domain";

export const MAX_RECENT_PROJECTS = 50;

function byUpdatedAt(
  left: Pick<StoredProject, "updatedAt">,
  right: Pick<StoredProject, "updatedAt">,
) {
  return (
    new Date(right.updatedAt).getTime() -
    new Date(left.updatedAt).getTime()
  );
}

function deduplicate(projects: StoredProject[]) {
  const seen = new Set<string>();
  return projects.filter((project) => {
    if (!project?.id || seen.has(project.id)) return false;
    seen.add(project.id);
    return true;
  });
}

export function enforceRecentProjectLimit(
  projects: StoredProject[],
  archivedAt = new Date().toISOString(),
) {
  const unique = deduplicate(projects);
  const recent = unique.filter((project) => !project.archivedAt).sort(byUpdatedAt);
  const archived = unique.filter((project) => project.archivedAt).sort(byUpdatedAt);
  const keptRecent = recent.slice(0, MAX_RECENT_PROJECTS);
  const overflow = recent.slice(MAX_RECENT_PROJECTS).map((project) => ({
    ...project,
    archivedAt,
  }));
  return [...keptRecent, ...overflow, ...archived];
}

export function upsertProject(
  projects: StoredProject[],
  snapshot: StoredProject,
  archivedAt = new Date().toISOString(),
) {
  const existing = projects.find((project) => project.id === snapshot.id);
  const nextSnapshot = {
    ...snapshot,
    archivedAt: snapshot.archivedAt || existing?.archivedAt,
  };
  return enforceRecentProjectLimit(
    [nextSnapshot, ...projects.filter((project) => project.id !== snapshot.id)],
    archivedAt,
  );
}

export function archiveProject(
  projects: StoredProject[],
  projectId: string,
  archivedAt = new Date().toISOString(),
) {
  return projects.map((project) =>
    project.id === projectId && !project.archivedAt
      ? { ...project, archivedAt }
      : project,
  );
}

export function restoreProject(
  projects: StoredProject[],
  projectId: string,
  restoredAt = new Date().toISOString(),
) {
  const restored = projects.map((project) =>
    project.id === projectId
      ? { ...project, archivedAt: undefined, updatedAt: restoredAt }
      : project,
  );
  return enforceRecentProjectLimit(restored, restoredAt);
}

export function deleteArchivedProject(
  projects: StoredProject[],
  projectId: string,
) {
  return projects.filter(
    (project) => project.id !== projectId || !project.archivedAt,
  );
}
