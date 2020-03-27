module TransactionService
  TransactionModel = ::Transaction

  class BookingStateChangeError < StandardError
  end

  TransitionMetadata= EntityUtils.define_builder(
    [:paypal_pending_reason, :symbol],
    [:paypal_payment_status, :symbol],
    [:user_id, :string],
    [:executed_by_admin, :bool]
  )

  module StateMachine
    module_function

    def transition_to(transaction_id, new_status, metadata = nil)
      new_status = new_status.to_sym

      if can_transition_to?(transaction_id, new_status)
        transaction = TransactionModel.where(id: transaction_id, deleted: false).first
        save_transition(transaction, new_status, metadata)
      end
    end

    def save_transition(transaction, new_status, metadata = nil)
      metadata_hash = Maybe(metadata)
        .map { |data| TransitionMetadata.call(data) }
        .map { |data| HashUtils.compact(data) }
        .or_else(nil)

      state_machine = TransactionProcessStateMachine.new(transaction, transition_class: TransactionTransition)
      state_machine.transition_to!(new_status, metadata_hash)

      transaction.touch(:last_transition_at) # rubocop:disable Rails/SkipsModelValidations

      transaction.reload
    end

    def can_transition_to?(transaction_id, new_status)
      transaction = TransactionModel.where(id: transaction_id, deleted: false).first
      if transaction
        state_machine = TransactionProcessStateMachine.new(transaction, transition_class: TransactionTransition)
        state_machine.can_transition_to?(new_status)
      end
    end
  end
end
