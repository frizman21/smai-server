class Admin::TenantsController < Admin::BaseController
  TENANT_PARAMS = %i[name company_name logo_url logo job_reference_required].freeze

  before_action :set_tenant, only: [:show, :edit, :update]

  def index
    @tenants = Tenant.order(:name)
  end

  def show
    @invitation = Invitation.new
    @pending_invitations = @tenant.invitations.where(accepted_at: nil).order(created_at: :desc)
    @users = @tenant.users.includes(:location, :email_delegations).order(:email)
    @locations = @tenant.locations.order(:display_name)
    @invite_locations = @tenant.locations.active.order(:display_name)
  end

  def new
    @tenant = Tenant.new
  end

  def create
    @tenant = Tenant.new(tenant_params)
    if @tenant.save
      AuditLogger.write(
        tenant: @tenant, actor: current_user,
        action: "tenant.create", target: @tenant,
        after: tenant_audit_snapshot(@tenant)
      )
      redirect_to admin_tenant_path(@tenant), notice: "Tenant '#{@tenant.name}' created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    before = tenant_audit_snapshot(@tenant)
    if @tenant.update(tenant_params)
      AuditLogger.write(
        tenant: @tenant, actor: current_user,
        action: "tenant.update", target: @tenant,
        before: before, after: tenant_audit_snapshot(@tenant)
      )
      redirect_to admin_tenant_path(@tenant), notice: "Tenant updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_tenant
    @tenant = Tenant.find(params[:id])
  end

  def tenant_params
    params.require(:tenant).permit(*TENANT_PARAMS)
  end

  def tenant_audit_snapshot(tenant)
    tenant.slice(:name, :company_name, :logo_url, :job_reference_required).merge(
      logo_attached: tenant.logo.attached?,
      logo_filename: tenant.logo.attached? ? tenant.logo.filename.to_s : nil
    )
  end
end
