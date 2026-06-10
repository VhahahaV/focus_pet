import FocusPetCore
import SwiftUI

struct PetSettingsView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("桌宠")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    StatusPill(title: model.petPlacementMode.title, symbol: "location.fill")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        PetPreviewCard()
                        PetSettingsControls()
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        PetPreviewCard()
                        PetSettingsControls()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct PetPreviewCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                PetSpriteAnimator(
                    catalog: model.currentPetCatalog,
                    action: model.currentPetAction,
                    fallbackState: model.currentState.userState,
                    animated: model.petAnimationEnabled
                )
                .frame(width: 224, height: 224)

                Label("\(Int(model.petSize)) px", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .offset(x: -8, y: -8)
            }

            VStack(spacing: 6) {
                Text(model.currentPetCatalog.pack?.name ?? "罗小黑")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.currentState.userState.title)
                    .font(.title3.weight(.semibold))
                Text(model.currentPetBehavior.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let bubble = model.currentPetBubble {
                PetSpeechBubble(message: bubble.message, compact: false)
            } else {
                PetSpeechBubble(message: model.lastReminderMessage, compact: false)
            }
        }
        .padding(20)
        .frame(width: 330, alignment: .top)
        .dashboardCard(.thinMaterial)
    }
}

struct PetSettingsControls: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PetSettingSection(title: "资源包", symbol: "shippingbox.fill") {
                Picker("当前桌宠", selection: Binding(
                    get: { model.selectedPetPackID },
                    set: { model.selectPetPack($0) }
                )) {
                    ForEach(model.availablePetPacks) { record in
                        Text(record.pack.name).tag(record.id)
                    }
                }

                HStack {
                    Button {
                        model.chooseAndImportPetPack()
                    } label: {
                        Label("导入本地宠物包", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        model.refreshPetPacks()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)

                if let record = model.availablePetPacks.first(where: { $0.id == model.selectedPetPackID }) {
                    PetPackMetadataView(record: record)
                }

                if let result = model.petImportResult, !result.warnings.isEmpty {
                    Text("最近导入提示：\(result.warnings.map(\.rawValue).joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = model.petImportErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PetSettingSection(title: "窗口", symbol: "macwindow") {
                Toggle("显示桌宠窗口", isOn: Binding(
                    get: { !model.petHidden },
                    set: { _ in model.togglePetVisibility() }
                ))

                Picker("位置", selection: Binding(
                    get: { model.petPlacementMode },
                    set: { model.setPetPlacement($0) }
                )) {
                    ForEach(PetPlacementMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        model.returnPetToDock()
                    } label: {
                        Label("Dock", systemImage: "dock.rectangle")
                    }
                    Button {
                        model.setPetPlacement(.bottomRightCorner)
                    } label: {
                        Label("右下角", systemImage: "arrow.down.right")
                    }
                }
                .buttonStyle(.bordered)
            }

            PetSettingSection(title: "表现", symbol: "wand.and.stars") {
                Toggle("开启动画", isOn: $model.petAnimationEnabled)
                    .onChange(of: model.petAnimationEnabled) { _, _ in model.updatePetWindowAppearance() }
                Toggle("Hover 信息", isOn: $model.petHoverMenuEnabled)
                    .onChange(of: model.petHoverMenuEnabled) { _, _ in model.updatePetWindowAppearance() }
                Toggle("提醒声音", isOn: $model.soundEnabled)
                    .onChange(of: model.soundEnabled) { _, _ in model.updatePetWindowAppearance() }
            }

            PetSettingSection(title: "显示", symbol: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("透明度")
                        Spacer()
                        Text("\(Int(model.petOpacity * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.petOpacity, in: 0.5...1.0) {
                        Text("透明度")
                    }
                    .onChange(of: model.petOpacity) { _, _ in model.updatePetWindowAppearance() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("大小")
                        Spacer()
                        Text("\(Int(model.petSize)) px")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { model.petSize },
                        set: { model.setPetSize($0) }
                    ), in: 96...160) {
                        Text("大小")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardCard(.regularMaterial)
    }
}

struct PetPackMetadataView: View {
    var record: PetPackRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    StatusPill(title: record.pack.source.rawValue, symbol: "tray.full.fill")
                    StatusPill(title: record.pack.distribution.rawValue, symbol: "lock.doc.fill")
                }

                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(title: record.pack.source.rawValue, symbol: "tray.full.fill")
                    StatusPill(title: record.pack.distribution.rawValue, symbol: "lock.doc.fill")
                }
            }

            if record.pack.distribution == .localOnly || record.pack.license?.type == "unknown" {
                Text("本地资源包，不上传。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !record.validation.errors.isEmpty {
                Text("不可播放项：\(record.validation.errors.map(\.rawValue).joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !record.validation.warnings.isEmpty {
                Text("提示：\(record.validation.warnings.map(\.rawValue).joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PetSettingSection<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
    }
}
