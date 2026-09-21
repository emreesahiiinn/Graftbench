import Foundation

/// A headless diagnostic that exercises the real git engine + parsers against a
/// repository. Run it by launching the app with the environment variable
/// `GRAFTBENCH_SELFTEST=/path/to/repo`; it prints a report and exits.
enum SelfTest {
    static func run(path: String) async {
        let url = URL(fileURLWithPath: path)
        do {
            let root = try await GitClient.discover(at: url)
            let client = GitClient(root: root)
            print("ROOT: \(root.path)")

            let status = try await client.status()
            print("STATUS branch=\(status.branch ?? "-") upstream=\(status.upstream ?? "-") " +
                  "ahead=\(status.ahead) behind=\(status.behind) entries=\(status.entries.count) " +
                  "staged=\(status.staged.count) unstaged=\(status.unstaged.count) conflicts=\(status.conflicted.count)")
            for e in status.entries.prefix(20) {
                print("  [\(e.primaryState.badge)] \(e.path) staged=\(e.isStaged) untracked=\(e.isUntracked)")
            }

            let commits = try await client.log(revisions: ["--branches", "--tags", "--remotes", "HEAD"], limit: 50)
            print("LOG commits=\(commits.count)")
            let graph = GraphLayout.compute(commits: commits)
            print("GRAPH laneCount=\(graph.laneCount) rows=\(graph.rows.count)")
            for (i, cm) in commits.prefix(14).enumerated() {
                let row = graph.rows[i]
                let refs = cm.refs.map { $0.name }.joined(separator: ",")
                print("  \(cm.shortSHA) col=\(row.column) w=\(row.width) edges=\(row.edges.count) " +
                      "parents=\(cm.parents.count) refs=[\(refs)] | \(cm.subject)")
            }

            let branches = try await client.branches()
            print("BRANCHES \(branches.count)")
            for b in branches {
                print("  \(b.isCurrent ? "*" : " ") \(b.name) remote=\(b.isRemote) " +
                      "up=\(b.upstream ?? "-") +\(b.ahead)/-\(b.behind) gone=\(b.upstreamGone)")
            }

            let remotes = try await client.remotes()
            print("REMOTES \(remotes.map { "\($0.name)=\($0.fetchURL)" })")
            let tags = try await client.tags()
            print("TAGS \(tags.map { $0.name })")
            let stashes = try await client.stashes()
            print("STASHES \(stashes.count) \(stashes.map { $0.message })")

            if let first = commits.first {
                let diffs = try await client.commitDiff(sha: first.id, firstParent: first.parents.first)
                print("COMMITDIFF files=\(diffs.count) firstHunks=\(diffs.first?.hunks.count ?? 0) " +
                      "+\(diffs.first?.addedLines ?? 0)/-\(diffs.first?.removedLines ?? 0)")
            }
            if let firstUnstaged = status.unstaged.first {
                let d = firstUnstaged.isUntracked
                    ? try await client.untrackedDiff(path: firstUnstaged.path)
                    : try await client.diff(path: firstUnstaged.path, staged: false)
                print("FILEDIFF \(firstUnstaged.path) hunks=\(d.hunks.count) +\(d.addedLines)/-\(d.removedLines) binary=\(d.isBinary)")
            }

            print("SELFTEST OK")
        } catch {
            print("SELFTEST FAIL: \(error)")
        }
    }
}
