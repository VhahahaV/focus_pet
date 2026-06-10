import FocusPetCore
import Foundation

@MainActor
final class PetEngine {
    private let behaviorController = PetBehaviorController()
    private var actionScheduler = PetActionScheduler()
    private let bubbleController = PetBubbleController()

    func behavior(
        for state: FusedUserState,
        previousState: FusedUserState?,
        latestReminder: ReminderDecision?
    ) -> PetBehaviorState {
        behaviorController.behavior(
            for: state,
            previousState: previousState,
            latestReminder: latestReminder
        )
    }

    func action(for behavior: PetBehaviorState, now: Date = Date()) -> PetAction {
        actionScheduler.nextAction(behavior: behavior, now: now)
    }

    func bubble(
        for state: FusedUserState,
        previousState: FusedUserState?,
        latestReminder: ReminderDecision?
    ) -> PetBubble? {
        bubbleController.bubble(
            for: state,
            previousState: previousState,
            latestReminder: latestReminder
        )
    }

    func lightInteractionBubble() -> PetBubble {
        bubbleController.lightInteractionBubble()
    }
}
