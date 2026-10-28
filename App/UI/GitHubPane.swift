import SwiftUI

struct GitHubPane: View {
    @EnvironmentObject private var github: GitHubSync
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                TextField("Pseudo GitHub", text: $github.username, prompt: Text("ex. octocat"))
                    .onSubmit { github.refresh() }
                HStack {
                    if github.isLoading {
                        ProgressView().controlSize(.small)
                        Text("Actualisation…").foregroundStyle(.secondary)
                    } else if let error = github.error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if let s = github.snapshot {
                        Text("\(s.total) contributions sur un an · \(s.today) aujourd'hui · série de \(s.streak) j")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Actualiser") { github.refresh() }
                        .disabled(github.username.trimmingCharacters(in: .whitespaces).isEmpty || github.isLoading)
                }
            } header: {
                Text("Compte")
            } footer: {
                Text("Sans jeton, le widget montre tes contributions publiques et tes commits sur les dépôts publics. Mise à jour toutes les 30 min.")
            }

            if let commits = github.snapshot?.commits, !commits.isEmpty {
                Section("Derniers commits") {
                    ForEach(commits) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.message).lineLimit(1)
                            Text("\(c.repo) · \(c.date.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if github.hasToken {
                    HStack {
                        Label("Jeton enregistré dans le trousseau", systemImage: "key.fill")
                        Spacer()
                        Button("Supprimer", role: .destructive) { github.setToken("") }
                    }
                } else {
                    SecureField("Jeton d'accès (facultatif)", text: $token)
                    Button("Enregistrer le jeton") {
                        github.setToken(token)
                        token = ""
                    }
                    .disabled(token.isEmpty)
                }
            } header: {
                Text("Contributions privées")
            } footer: {
                Text("Pour inclure tes dépôts privés : github.com → Settings → Developer settings → Personal access tokens → Fine-grained, accès en lecture seule. Le jeton reste dans le trousseau macOS.")
            }
        }
        .formStyle(.grouped)
    }
}
