class Contrato < ApplicationRecord

  belongs_to :cliente, inverse_of: :contratos
  belongs_to :plan, inverse_of: :contratos
  belongs_to :cobrador

  has_many :pagos, -> { eager_load(:plan).order(:id) } , dependent: :restrict_with_error , inverse_of: :contrato do 
    def por_ano(ano)
      where(ano: ano)
    end 
  end 

  has_many :beneficiarios, dependent: :restrict_with_error, inverse_of: :contrato

  enum  estado: {
    creado: "CREADO",
    activo: "ACTIVO",
    anulado: "ANULADO",
    vencido: "VENCIDO"
  }    

  before_update do 
    if creado?
      Pago.where(contrato_id: id, ano: Date.today.year).delete_all
      self.hasta = Date.new(Date.today.year,12,31)
      desdeweek = desde.cweek()
      desdeweek = 1 if(desdeweek >= 52)
      generar_pagos(self.desde.year,desdeweek)
    end 
  end 

  before_create do
    self.hasta =  Date.new(Date.today.year,12,31)
    desdeweek = desde.cweek()
    desdeweek = 1  if(desdeweek >= 52)
    generar_pagos(self.desde.year,desdeweek)
  end


  def self.search(page = 1 , search , sort)
    search ||= ""
    sort ||= "" 
    if search.empty? 
      paginate(page: page).cargar_detalle.order(id: :desc)
    else
      if sort == "cliente"
        paginate(page: page).
          cargar_detalle.
          where("clientes.nombres||' '||clientes.identidad  like ?","%#{search}%").order("clientes.nombres")
      elsif sort == "plan"
        paginate(page: page).cargar_detalle.where("planes.nombre like ?","%#{search}%").order("planes.nombre")
      elsif sort == "Numero"
        paginate(page: page).cargar_detalle.where("contratos.id::text like ?","%#{search.to_i}%").order("contratos.id asc")
      else 
        paginate(page: page).cargar_detalle.where("#{sort} like ?","%#{search}%").order("#{sort} asc")
      end 
    end 
  end     

  def self.cargar_detalle
    eager_load(:cliente,:plan)
  end 

  def generar_pagos_proximo_periodo(ano)
    if(ano > self.desde.year)
      self.desde = Date.new(ano,1,1)
      self.hasta = Date.new(ano,12,31)
      generar_pagos(ano,1)
      save()
    else
      errors.add(:estado,"No puedes generar pago de este año, dado que es el año entransito del contrato.")
    end 
    errors.empty?
  end 


  def anular() 
    if creado?
      Contrato.transaction do
        self.monto = 0.0
        self.total = 0.0
        self.estado = "ANULADO"
        self.pagos.update_all(estado: "anulado")
        save!()
      end 
    else 
      self.errors.add(:estado, "No Puedes Anular este Contrato. se encuenta #{self.estado}.")
    end 
    errors.empty?
  end 


  # CREADO -> ACTIVO -> ANULADO -> VENCIDO
  def cambiar_plan(plan_params) 
    plan = Plan.find(plan_params[:plan_id])
    unless ["CREADO","ACTIVO"].include?(self.estado) 
      self.errors.add(:estado, "No Puedes Cambiar el Plan,este Contrato. se encuenta #{self.estado}")
    else 
      ano = Date.today.year()
      semana = Date.today.cweek()
      Contrato.transaction do
        self.plan = plan 
        ano = Pago.arel_table[:ano]
        _semana =  Pago.arel_table[:semana]
        estado =  Pago.arel_table[:estado]
        self.pagos
          .where(ano.eq(ano))
          .where(_semana.gteq(semana))
          .where(estado.eq("pendiente"))
          .update_all(monto: plan.monto,plan_id: plan.id)
        self.total = self.pagos.sum(:monto)
        save!()
      end 
    end 
    errors.empty?
  end 

  def activar() 
    if creado?
      activo!
    else 
      self.errors.add(:estado, "No Puedes Activar este Contrato. se encuenta #{self.estado}")
    end 
    errors.empty?
  end 

  def pagar(pago_id)
    if activo?
      Contrato.transaction do
        pendiente = 0.0 
        pagos(true).eager_load(:plan).each do |pago|
          if(pago.id == pago_id.to_i)
            pago.estado = "pagado"
            pago.plan = self.plan 
            pago.cobrador = self.cobrador
            pago.fecha_pago = Date.today 
            pago.save!()
          else 
            pendiente += pago.monto if(pago.estado == "pendiente")        
          end 
        end
        self.monto = pendiente
        self.update!({monto: pendiente})
      end 
    end 
  end 

  def no_anulado?
    !anulado?
  end 

  def inactivo?
    !activo?
  end 

  def monto_pendiente ano=Date.today.year
    self.pagos.where(estado: "pendiente",ano: ano).sum(:monto)
  end 

  def total_ano  ano=Date.today.year 
    self.pagos.where(ano: ano).sum(:monto)
  end 

  def ultimo_monto(ano=Date.today.year)
    self.pagos.where(ano: ano).last.monto
  end 

  validates :cliente_id, 
      presence: {message: 'Seleccione'}

  validates :desde, 
      presence: {message: 'Ingrese'}

  #validates :hasta,presence: {message: 'Ingrese'}

  validates :plan_id, presence: {message: 'Seleccione'}

  #validates :fecha_registro, presence: {message: 'Ingrese Fecha de Registro'}

  validate :fecha_valida? 

  self.per_page = 12 

  private 
  
    def generar_pagos(ano,semana_incial)
      _deuda = 0.0 
      (semana_incial..52).each do  |n| 
        self.pagos << Pago.new({semana: n, monto: plan.monto, plan_id: plan.id, ano: ano })
       _deuda += plan.monto
      end 
      self.monto = _deuda
      self.total = _deuda
    end 

    def fecha_valida?
      if !desde.nil? and desde.year != Date.today.year 
        errors.add(:desde,"Error el año debe ser el año actual.")
      end 
      errors.empty?
    end

end
