class UsersController < ApplicationController
  EDITABLE_PARAMS = %i[first_name last_name title phone_number location_id].freeze

  before_action :load_user, only: [:edit, :update]
  before_action :require_admin_access, only: [:edit, :update]

  def index
    @tenant = current_user.tenant
    if @tenant
      @users = @tenant.users.includes(:email_delegations, :location).order(:email)
      # Pending invitations only flow to the view for users who can act on
      # them (account admins / app admins). Regular tenant users get an
      # empty relation so the data never crosses the controller boundary.
      @pending_invitations = if current_user.can_invite_into_tenant?
        @tenant.invitations.where(accepted_at: nil).order(created_at: :desc)
      else
        Invitation.none
      end
      @invite_locations = @tenant.locations.active.order(:display_name)
      @reply_ignored_domains = @tenant.reply_ignored_domains
    else
      @users = User.none
      @pending_invitations = Invitation.none
      @invite_locations = Location.none
      @reply_ignored_domains = []
    end
    @invitation = Invitation.new
  end

  def edit
    @location_options = current_user.tenant.locations.active.order(:display_name)
  end

  def update
    before = audit_snapshot(@user)
    if @user.update(user_params)
      AuditLogger.write(
        tenant: current_user.tenant, actor: current_user,
        action: "user.update", target: @user,
        before: before, after: audit_snapshot(@user)
      )
      redirect_to users_path, notice: "Updated #{@user.display_name}."
    else
      @location_options = current_user.tenant.locations.active.order(:display_name)
      render :edit, status: :unprocessable_content
    end
  end

  private

  # Operator path: only tenant admins / app admins can edit; only members
  # of the current user's tenant. SMAI-staff cross-tenant edits live on
  # the admin namespace separately.
  def load_user
    @user = current_user.tenant&.users&.find_by(id: params[:id])
    if @user.nil?
      redirect_to users_path, alert: "User not found in your team." and return
    end
  end

  def require_admin_access
    return if current_user.can_invite_into_tenant?
    redirect_to users_path, alert: "Only account admins can edit teammates."
  end

  def user_params
    attrs = params.require(:user).permit(*EDITABLE_PARAMS)
    # Defense in depth: even when the form posts a location_id, drop it
    # if the picked location doesn't belong to current_user's tenant.
    if attrs[:location_id].present? &&
       !current_user.tenant.locations.exists?(id: attrs[:location_id])
      attrs = attrs.except(:location_id)
    end
    attrs
  end

  def audit_snapshot(user)
    user.slice(:first_name, :last_name, :title, :phone_number, :location_id)
  end
end
