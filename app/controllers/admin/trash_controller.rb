# Admin-only listing of soft-deleted Campaigns, JobProposals, and Users.
# Restore actions live on the respective controllers
# (Admin::CampaignsController#restore, JobProposalsController#restore,
# Admin::UsersController#restore) — this controller is just the inbox view.
class Admin::TrashController < Admin::BaseController
  def show
    @discarded_campaigns = Campaign.with_discarded.discarded
      .includes(:approved_by_user)
      .order(discarded_at: :desc)

    @discarded_proposals = JobProposal.with_discarded.discarded
      .includes(:location, :owner, :tenant)
      .order(discarded_at: :desc)

    @discarded_users = User.discarded
      .includes(:tenant)
      .order(discarded_at: :desc)
  end
end
