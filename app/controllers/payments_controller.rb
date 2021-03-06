class PaymentsController < ApplicationController
  before_filter :only => [:home, :all] do |controller|
    controller.ensure_logged_in "you_must_log_in_to_perform_transactions"
  end

  def home
    if request.post?
      @code=params[:code]
      if @code.length>0
        @payment=Payment.find_by_receipt(@code)
        Rails.logger.debug { "Using the code "+@code.to_s }
      else
        flash[:error]="Please enter the correct transaction code in the field below"
        Rails.logger.debug { "Failed to get the code "+@code.to_s }
        #redirect_to :action=>"home",:id=>params[:listing_id] #disallow null values on that page
      end
      if @payment
        #save the payment and tag it to this listing and this user
        unless @payment.amount.nil?
          @payjob = JobPayment.new
          @payjob.payment_id=@payment.id
          @payjob.user_id=@current_user.id.to_s
          @payjob.listing_id=params[:listing_id].to_i
          if @payjob.save

          if params[:service_id] && !params[:service_id].to_s.blank?
              service = Service.find(params[:service_id])
              if service
                if service.update_attribute(:status, "pending")
                  flash[:notice]="Payment (#{@payment.amount.to_s})successfully processed. The owner of the job will be notified to deliver your order"

                  redirect_to services_path(:type=>"shopped") and return
                end
              end
            else
              @listingq=Listing.find(params[:listing_id].to_i)
              @service = Service.new
              @service.author_id=@listingq.author_id
              @service.receiver_id= @current_user.id.to_s
              @service.listing_id=@listingq.id
              @service.title=@listingq.title
              @service.status="pending"
            end
            if @service.save
              #TODO create a job to notify both parties and create skeleton services
              flash[:notice]="Your payment of #{@payment.amount.to_s} was processed. The owner has been informed and they shall deliver your product soon"
              #mail user and service buyer
                  begin

                  PersonMailer.service_bought_notification(@current_user,Listing.find(params[:listing_id].to_i),request.host).deliver
                  rescue Exception=>e
                    Rails.logger.error{e}
                    end
              redirect_to listing_path(params[:listing_id].to_i)
            end
          else
            flash[:error]="There was an error processing your payment of #{@payment.amount} "
            return
          end
        end
      else
        flash[:error]="No such transaction exists or you've entered the incorrect code.please try again in a few moments"
        redirect_to :action=>"home", :id=>params[:listing_id]
        #return
      end
    else
      @listing_id=params[:id]
      #@stat=params[:stat].to_s.eql?("re") ? params[:stat].to_s : nil
      @service= params[:serv_id]? params[:serv_id].to_s : nil
      if !@listing_id.nil?
        @listing=Listing.find_by_id(@listing_id)
        if !@listing.nil?
          #Load the form with the listing details
        else
          flash.now[:error]="No listing could be found with the given parameters"
          redirect_to :action=>"home", :id=>params[:listing_id] and return
        end
      else
        flash[:error]="Please select a listing that you wish to order from the listings page"
        redirect_to :action=>"home" and return
      end
    end
  end

  def all
    @to_render = {:layout => "wallet"}
    @payments = Payment.all
    render @to_render

  end

  def new

    #message = "BR53WA470 Confirmed. Ksh5,040.00 sent to KELVIN NKINYILI 0700335924 on 1/10/11 at 1:29 PM New M-PESA balance is Ksh0.00"
    message = "CA69NM170 Confirmed. You have received Ksh5,040.00 from ROY RUTTO 254721574146 on 15/2/12 at 1:42 PM New M-PESA balance is Ksh5050.00"
    #message = "You have received blah blah"
    transaction = Parser.parse(message)
    #Create a payment object
    #Not necessary if the items are correctly name
    @payment = Payment.new
    @payment.account_id = transaction["ACCOUNT"]
    @payment.super_type = transaction["SUPER_TYPE"]
    @payment.receipt = transaction["RECEIPT"]
    @payment.transaction_type = transaction["TYPE"]
    @payment.time =transaction["TIME"]
    @payment.phonenumber = transaction["PHONE"]
    @payment.name = transaction["NAME"]
    @payment.account =transaction["ACCOUNT"]
    @payment.status = transaction["STATUS"]
    @payment.amount = transaction["AMOUNT"].gsub(",", "")
    @payment.post_balance = transaction["BALANCE"].gsub(",", "")
    @payment.transaction_cost = transaction["COSTS"].eql? 0 ? 0 :transaction["COSTS"].gsub(",", "")
    @payment.note = transaction["NOTE"]

    Rails.logger.debug { transaction }
    if @payment.save
      Rails.logger.info { "Successfully created a transaction" }
      redirect_to :action => "all"
    else
      Rails.logger.error { "Payment processing failed" }
      flash[:error] = "Payment processing failed"
    end


  end

  def show
  end

  def confirm

  end

  def cashflow
    @title = params[:type]
    if @title.eql? "received"
      @payments = Cashflow.find_by_direction("received", @current_user.id).paginate(:per_page => 15, :page => params[:page])
    elsif @title.eql? "sent"
      @payments = Cashflow.find_by_direction("sent", @current_user.id).paginate(:per_page => 15, :page => params[:page])
    end
    @to_render = {:layout => "wallet"}
    Rails.logger.debug { @payments.inspect }
    render @to_render

  end

  def cashaccount
    @to_render = {:layout => "wallet"}
    @payments = Cashflow.find_by_direction("both", @current_user.id).paginate(:per_page => 15, :page => params[:page])
    render @to_render

  end
  def withdraw

    if request.post?
      #last transaction balance
      @bal = params[:amount_bf]
      if params[:amount]
        if params[:amount]>@bal
          flash[:error]="Error,the amount is greater than your balance"
          redirect_to :controller=>"payments",:action=>"cashaccount" and return
        end
      else
        flash[:error]="Error,please input an amount"
        redirect_to :controller=>"payments",:action=>"cashaccount" and return
      end
      @cashflow= Cashflow.new
      @cashflow.user_id= params[:user_id]
      @cashflow.sender_user_id=params[:sender_user_id]
      @cashflow.amount=params[:amount]
      @cashflow.current_balance=(@bal.to_f - @cashflow.amount.to_f).to_f
      @cashflow.transaction_type=1

      if @cashflow.save
        flash[:notice]="Successfully withdrawn amount. You will receive it in your MPESA account in less than 24hrs"
        #MoneyAccount.withdraw(@current_user.id,1000)
        redirect_to :controller=>"payments",:action=>"cashaccount"
      end
    else
      @cashflow = Cashflow.new
      @cashflow.user_id=@current_user.id.to_s
      #TODO get a good user to be sender
      @cashflow.sender_user_id="PAYBILL"
      @cashflow.amount=params[:bb_f]
      @to_render = {:layout => "wallet"}
      render @to_render
      end


    end
end
