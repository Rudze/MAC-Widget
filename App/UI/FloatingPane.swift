import SwiftUI

struct FloatingPane: View {
    @EnvironmentObject private var floating: FloatingWidgets

    var body: some View {
        Form {
            Section {
                Toggle("Activer les widgets flottants", isOn: $floating.isEnabled)
            } footer: {
                Text("Option facultative. Désactivée, tout se gère uniquement depuis la galerie de widgets de macOS. Activée, l'app pose en plus ses propres widgets sur le bureau, qui peuvent avoir un fond vraiment transparent.")
            }

            if floating.isEnabled {
                Section {
                    ForEach($floating.items) { $item in
                        HStack {
                            Toggle(isOn: $item.enabled) {
                                Label(item.kind.label, systemImage: item.kind.symbol)
                            }
                            Spacer()
                            Picker("", selection: $item.size) {
                                ForEach(FloatingSize.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .disabled(!item.enabled)
                        }
                    }
                } header: {
                    Text("Widgets affichés")
                } footer: {
                    Text("Posés sur le bureau, sous tes fenêtres. Choisis le fond « Aucun » dans l'onglet Apparence pour qu'ils soient transparents.")
                }

                Section {
                    Toggle("Déplacer les widgets flottants", isOn: $floating.editing)
                        .disabled(!floating.anyShown)
                } footer: {
                    Text("Active, fais glisser chaque widget où tu veux, puis désactive : les clics les traversent à nouveau. Aussi dans le menu de la barre des menus.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
