class ShortLinksController < ApplicationController
  # Public redirect — recipients of the SMS will hit this endpoint
  # straight from their phone before they're signed in. Skip the
  # app-wide authentication guard for this one action.
  skip_before_action :authenticate_user!, only: :show

  def show
    link = ShortLink.find_by(code: params[:id])
    if link
      redirect_to link.target_url, allow_other_host: true, status: :found
    else
      render plain: "Link not found", status: :not_found
    end
  end
end
