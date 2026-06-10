import FocusPetCore
import Foundation

@MainActor
final class PetBubbleController {
    private var lightIndex = 0
    private var distractedIndex = 0
    private var entertainmentIndex = 0
    private var welcomeIndex = 0

    func bubble(
        for state: FusedUserState,
        previousState: FusedUserState?,
        latestReminder: ReminderDecision?
    ) -> PetBubble? {
        if previousState?.userState == .away, state.userState != .away {
            return welcomeBackBubble()
        }

        guard let latestReminder else {
            return nil
        }

        if latestReminder.ruleID == FocusRule.entertainmentDistraction.id || state.context == .entertainment {
            return entertainmentBubble()
        }

        if latestReminder.userState == .distracted {
            return distractedBubble()
        }

        return nil
    }

    func lightInteractionBubble() -> PetBubble {
        let messages = [
            "我在这里，不打扰你。",
            "今天已经陪你一会儿啦。",
            "要不要喝口水？",
            "继续保持。"
        ]
        defer { lightIndex = (lightIndex + 1) % messages.count }
        return PetBubble(kind: .light, message: messages[lightIndex])
    }

    private func distractedBubble() -> PetBubble {
        let messages = [
            "刚才好像有点飘走了，要回到任务吗？",
            "罗小黑轻轻提醒你：回来啦。",
            "先回到当前任务，晚点再分心。"
        ]
        defer { distractedIndex = (distractedIndex + 1) % messages.count }
        return PetBubble(
            kind: .distracted,
            message: messages[distractedIndex],
            primaryActionTitle: "回到任务"
        )
    }

    private func entertainmentBubble() -> PetBubble {
        let messages = [
            "已经娱乐一会儿啦，要不要收个尾？",
            "这集看完就回去？我帮你记着。",
            "罗小黑等你收个尾，再回到任务。"
        ]
        defer { entertainmentIndex = (entertainmentIndex + 1) % messages.count }
        return PetBubble(
            kind: .entertainment,
            message: messages[entertainmentIndex],
            primaryActionTitle: "继续 10 分钟",
            secondaryActionTitle: "回到工作"
        )
    }

    private func welcomeBackBubble() -> PetBubble {
        let messages = [
            "欢迎回来，要继续刚才的任务吗？",
            "刚才你离开了一会儿，我帮你暂停统计了。"
        ]
        defer { welcomeIndex = (welcomeIndex + 1) % messages.count }
        return PetBubble(
            kind: .welcomeBack,
            message: messages[welcomeIndex],
            primaryActionTitle: "继续",
            secondaryActionTitle: "今天状态"
        )
    }
}
