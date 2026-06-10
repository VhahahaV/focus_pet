import AppKit
import FocusPetCore
import SwiftUI

struct PetInteractionView: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var lastDragTranslation = CGSize.zero
    @State private var isDragging = false

    var body: some View {
        PetSpriteAnimator(
            catalog: model.currentPetCatalog,
            action: model.currentPetAction,
            fallbackState: model.currentState.userState,
            animated: model.petAnimationEnabled
        )
        .frame(width: model.petSize, height: model.petSize)
        .contentShape(Rectangle())
        .onHover { inside in
            model.handlePetHoverChanged(inside)
            if inside {
                PetWindowController.shared.showHoverMenu(model: model)
            } else {
                PetWindowController.shared.scheduleHoverMenuHide()
            }
        }
        .gesture(tapGesture)
        .simultaneousGesture(dragGesture)
        .contextMenu {
            Button(model.isPaused ? "继续检测" : "暂停检测") {
                model.togglePause()
            }
            Button("隐藏 30 分钟") {
                model.hidePet(for: 30 * 60)
            }
            Button("回到 Dock 上方") {
                model.returnPetToDock()
            }
            Button("放到右下角") {
                model.setPetPlacement(.bottomRightCorner)
            }
            Button("设置") {
                model.openMainWindow(tab: .pet)
            }
            Divider()
            Button("退出 Focus Pet") {
                NSApp.terminate(nil)
            }
        }
        .onChange(of: model.currentPetBubble) { _, _ in
            PetWindowController.shared.updateBubble(model: model)
        }
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                model.handlePetDoubleClick()
            }
            .exclusively(before: TapGesture(count: 1).onEnded {
                model.handlePetSingleClick()
            })
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    model.handlePetDragBegan()
                }
                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                PetWindowController.shared.moveBy(delta: delta)
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                isDragging = false
                lastDragTranslation = .zero
                PetWindowController.shared.finishDrag(model: model)
            }
    }
}
