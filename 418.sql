-- ============================================================================
-- SMART POS PRO — DATABASE SCHEMA (CLEANED)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. CATEGORIES
-- ----------------------------------------------------------------------------
create table if not exists categories (
  id            uuid primary key,
  name          text not null,
  icon          text default '📁',
  color         text default '#4F46E5',
  display_order integer default 0,
  parent_id     uuid references categories(id) on delete set null,
  created_at    timestamptz not null default now()
);

alter table categories add column if not exists parent_id     uuid references categories(id) on delete set null;
alter table categories add column if not exists icon          text default '📁';
alter table categories add column if not exists color         text default '#4F46E5';
alter table categories add column if not exists display_order integer default 0;
create index if not exists idx_categories_parent on categories(parent_id);

-- ----------------------------------------------------------------------------
-- 2. PRODUCTS
-- ----------------------------------------------------------------------------
create table if not exists products (
  id               uuid primary key,
  sku              text unique,
  name             text not null,
  image_url        text,
  min_stock_alert  numeric not null default 5,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

alter table products add column if not exists sku              text;
alter table products add column if not exists image_url        text;
alter table products add column if not exists min_stock_alert  numeric not null default 5;
alter table products add column if not exists is_active        boolean not null default true;
alter table products add column if not exists updated_at       timestamptz not null default now();
create index if not exists idx_products_name on products using gin (to_tsvector('simple', name));
create index if not exists idx_products_active on products(is_active);

do $$
declare
  v_dup record;
  v_found boolean := false;
begin
  for v_dup in
    select sku, count(*) as n from products where sku is not null group by sku having count(*) > 1
  loop
    v_found := true;
    raise notice 'SKU ซ้ำ: "%" พบ % รายการ', v_dup.sku, v_dup.n;
  end loop;
end $$;

do $$ begin
  create unique index idx_products_sku_unique on products(sku) where sku is not null;
exception when unique_violation then
  raise notice 'ข้าม unique index บน products.sku — มี SKU ซ้ำอยู่ในข้อมูลจริง';
when duplicate_table then null;
end $$;

-- ----------------------------------------------------------------------------
-- 3. PRODUCT_CATEGORIES
-- ----------------------------------------------------------------------------
create table if not exists product_categories (
  product_id  uuid not null references products(id) on delete cascade,
  category_id uuid not null references categories(id) on delete cascade,
  primary key (product_id, category_id)
);
create index if not exists idx_prodcat_category on product_categories(category_id);

-- ----------------------------------------------------------------------------
-- 4. PRODUCT_VARIANTS
-- ----------------------------------------------------------------------------
create table if not exists product_variants (
  id              uuid primary key,
  product_id      uuid not null references products(id) on delete cascade,
  variant_name    text not null default 'ปกติ',
  barcode         text,
  price           numeric not null default 0 check (price >= 0),
  cost_price      numeric not null default 0 check (cost_price >= 0),
  stock_quantity  numeric not null default 0,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

alter table product_variants add column if not exists barcode        text;
alter table product_variants add column if not exists cost_price     numeric not null default 0;
alter table product_variants add column if not exists is_active      boolean not null default true;

do $$ begin
  create unique index idx_variants_barcode on product_variants(barcode) where barcode is not null;
exception when unique_violation then
  raise notice 'ข้าม unique index บน product_variants.barcode — มีบาร์โค้ดซ้ำอยู่ในข้อมูลจริง';
when duplicate_table then null;
end $$;
create index if not exists idx_variants_product on product_variants(product_id);

-- ----------------------------------------------------------------------------
-- 5. PRODUCT_FRACTIONS
-- ----------------------------------------------------------------------------
create table if not exists product_fractions (
  id              uuid primary key,
  variant_id      uuid not null references product_variants(id) on delete cascade,
  fraction_name   text not null,
  quantity_ratio  numeric not null check (quantity_ratio > 0),
  price           numeric not null default 0 check (price >= 0),
  barcode         text
);
alter table product_fractions add column if not exists barcode text;
create index if not exists idx_fractions_variant on product_fractions(variant_id);

-- ----------------------------------------------------------------------------
-- 6. CUSTOMERS
-- ----------------------------------------------------------------------------
create table if not exists customers (
  id            uuid primary key,
  name          text not null,
  phone         text,
  address       text default '',
  credit_limit  numeric not null default 0,
  debt          numeric not null default 0,
  created_at    timestamptz not null default now()
);
alter table customers add column if not exists phone        text;
alter table customers add column if not exists address      text default '';
alter table customers add column if not exists credit_limit numeric not null default 0;
alter table customers add column if not exists debt          numeric not null default 0;

-- ----------------------------------------------------------------------------
-- 7. SUPPLIERS
-- ----------------------------------------------------------------------------
create table if not exists suppliers (
  id          uuid primary key,
  name        text not null,
  phone       text,
  address     text default '',
  created_at  timestamptz not null default now()
);
alter table suppliers add column if not exists phone   text;
alter table suppliers add column if not exists address text default '';

-- ----------------------------------------------------------------------------
-- 8. APP_USERS
-- ----------------------------------------------------------------------------
create table if not exists app_users (
  id            uuid primary key,
  auth_user_id  uuid references auth.users(id) on delete set null,
  name          text not null,
  pin           text not null,
  role          text not null default 'CASHIER' check (role in ('OWNER','MANAGER','CASHIER')),
  permissions   jsonb not null default '[]'::jsonb,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
alter table app_users add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
alter table app_users add column if not exists permissions  jsonb not null default '[]'::jsonb;
alter table app_users add column if not exists is_active    boolean not null default true;

do $$ begin
  create unique index idx_app_users_auth on app_users(auth_user_id) where auth_user_id is not null;
exception when unique_violation then null;
end $$;

do $$ begin
  create unique index idx_app_users_one_owner on app_users((role = 'OWNER')) where role = 'OWNER';
exception when unique_violation then null;
end $$;

-- ----------------------------------------------------------------------------
-- 9. SHIFTS
-- ----------------------------------------------------------------------------
create table if not exists shifts (
  id            uuid primary key,
  opened_at     timestamptz not null,
  closed_at     timestamptz,
  opening_cash  numeric not null default 0,
  closing_cash  numeric,
  status        text not null default 'OPEN' check (status in ('OPEN','CLOSED')),
  opened_by     uuid references app_users(id),
  closed_by     uuid references app_users(id)
);
alter table shifts add column if not exists opening_cash numeric not null default 0;
alter table shifts add column if not exists closing_cash numeric;
alter table shifts add column if not exists opened_by    uuid references app_users(id);
alter table shifts add column if not exists closed_by    uuid references app_users(id);
create index if not exists idx_shifts_status on shifts(status);

-- ----------------------------------------------------------------------------
-- 10. BILLS
-- ----------------------------------------------------------------------------
create table if not exists bills (
  id                uuid primary key,
  bill_number       text not null unique,
  customer_id       uuid references customers(id),
  user_id           uuid references app_users(id),
  shift_id          uuid references shifts(id),
  subtotal          numeric not null default 0,
  discount_amount   numeric not null default 0,
  tax_amount        numeric not null default 0,
  total             numeric not null default 0,
  payment_method    text not null default 'CASH',
  status            text not null default 'PAID' check (status in ('PAID','CANCELLED')),
  created_at        timestamptz not null default now()
);

alter table bills add column if not exists shift_id        uuid references shifts(id);
alter table bills add column if not exists discount_amount numeric not null default 0;
alter table bills add column if not exists tax_amount      numeric not null default 0;
alter table bills add column if not exists status          text not null default 'PAID';
alter table bills alter column created_at set default now();
create index if not exists idx_bills_shift on bills(shift_id);
create index if not exists idx_bills_customer on bills(customer_id);
create index if not exists idx_bills_created on bills(created_at);

-- ----------------------------------------------------------------------------
-- 11. BILL_ITEMS
-- ----------------------------------------------------------------------------
create table if not exists bill_items (
  id            uuid primary key,
  bill_id       uuid not null references bills(id) on delete cascade,
  product_id    uuid references products(id),
  variant_id    uuid references product_variants(id),
  fraction_id   uuid references product_fractions(id),
  item_name     text not null,
  quantity      numeric not null,
  unit_price    numeric not null,
  line_total    numeric not null
);
alter table bill_items add column if not exists fraction_id uuid references product_fractions(id);
create index if not exists idx_bill_items_bill on bill_items(bill_id);

-- ----------------------------------------------------------------------------
-- 12. PURCHASE_ORDERS / PURCHASE_ORDER_ITEMS
-- ----------------------------------------------------------------------------
create table if not exists purchase_orders (
  id             uuid primary key default gen_random_uuid(),
  po_number      text,
  supplier_id    uuid references suppliers(id),
  status         text not null default 'ORDERED' check (status in ('ORDERED','RECEIVED','CANCELLED')),
  document_ref   text,
  credit_terms   integer default 30,
  ordered_at     timestamptz not null default now(),
  received_at    timestamptz
);
alter table purchase_orders add column if not exists document_ref text;
alter table purchase_orders add column if not exists credit_terms integer default 30;
alter table purchase_orders add column if not exists received_at  timestamptz;

create table if not exists purchase_order_items (
  id                    uuid primary key default gen_random_uuid(),
  purchase_order_id     uuid not null references purchase_orders(id) on delete cascade,
  product_id            uuid references products(id),
  variant_id            uuid references product_variants(id),
  quantity              numeric not null,
  unit_cost             numeric not null default 0,
  received_quantity     numeric not null default 0
);
alter table purchase_order_items add column if not exists received_quantity numeric not null default 0;

-- ----------------------------------------------------------------------------
-- 13. INVENTORY_MOVEMENTS
-- ----------------------------------------------------------------------------
create table if not exists inventory_movements (
  id           uuid primary key default gen_random_uuid(),
  variant_id   uuid not null references product_variants(id),
  change_qty   numeric not null,
  reason       text not null,
  ref_type     text,
  ref_id       uuid,
  created_at   timestamptz not null default now()
);
alter table inventory_movements add column if not exists ref_type text;
alter table inventory_movements add column if not exists ref_id   uuid;
create index if not exists idx_inv_move_variant on inventory_movements(variant_id);

-- ----------------------------------------------------------------------------
-- 14. CASH_LEDGER & ACCOUNTS_PAYABLE
-- ----------------------------------------------------------------------------
create table if not exists cash_ledger (
  id           uuid primary key default gen_random_uuid(),
  shift_id     uuid references shifts(id),
  type         text not null,
  income       numeric not null default 0,
  expense      numeric not null default 0,
  description  text,
  ref_id       text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_cash_ledger_shift on cash_ledger(shift_id);

create table if not exists accounts_payable (
  id                 uuid primary key,
  supplier_id        uuid references suppliers(id),
  purchase_order_id  uuid references purchase_orders(id) on delete set null,
  doc_ref            text,
  amount             numeric not null default 0 check (amount >= 0),
  credit_terms       integer default 30,
  status             text not null default 'OPEN' check (status in ('OPEN','PAID')),
  created_at         timestamptz not null default now(),
  paid_at            timestamptz
);
alter table accounts_payable add column if not exists paid_at timestamptz;
create index if not exists idx_ap_supplier on accounts_payable(supplier_id);
create index if not exists idx_ap_status   on accounts_payable(status);

-- ============================================================================
-- 15. HELPER FUNCTIONS
-- ============================================================================
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    where p.proname in ('bootstrap_first_owner', 'create_sale', 'receive_purchase_order', 'process_return', 'receive_customer_payment', 'adjust_stock')
      and pg_function_is_visible(p.oid)
  loop
    execute format('drop function if exists %s cascade;', r.sig);
  end loop;
end $$;

create or replace function is_staff() returns boolean
language sql security definer stable as $$
  select exists (select 1 from app_users where auth_user_id = auth.uid() and is_active);
$$;

create or replace function is_manager() returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from app_users
    where auth_user_id = auth.uid() and is_active and role in ('OWNER','MANAGER')
  );
$$;

create or replace function is_owner() returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from app_users where auth_user_id = auth.uid() and is_active and role = 'OWNER'
  );
$$;

-- ============================================================================
-- 16. ROW LEVEL SECURITY
-- ============================================================================
alter table categories           enable row level security;
alter table products             enable row level security;
alter table product_categories   enable row level security;
alter table product_variants     enable row level security;
alter table product_fractions    enable row level security;
alter table customers            enable row level security;
alter table suppliers            enable row level security;
alter table app_users            enable row level security;
alter table shifts               enable row level security;
alter table bills                enable row level security;
alter table bill_items           enable row level security;
alter table purchase_orders      enable row level security;
alter table purchase_order_items enable row level security;
alter table inventory_movements  enable row level security;
alter table cash_ledger          enable row level security;
alter table accounts_payable     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['categories','products','product_categories','product_variants',
                            'product_fractions','customers','shifts','bills','bill_items',
                            'purchase_orders','purchase_order_items','inventory_movements','cash_ledger',
                            'accounts_payable']
  loop
    execute format('drop policy if exists "staff_select_%1$s" on %1$s;', t);
    execute format('drop policy if exists "staff_insert_%1$s" on %1$s;', t);
    execute format('drop policy if exists "staff_update_%1$s" on %1$s;', t);
    execute format('drop policy if exists "manager_delete_%1$s" on %1$s;', t);
    execute format('create policy "staff_select_%1$s" on %1$s for select using (is_staff());', t);
    execute format('create policy "staff_insert_%1$s" on %1$s for insert with check (is_staff());', t);
    execute format('create policy "staff_update_%1$s" on %1$s for update using (is_staff()) with check (is_staff());', t);
    execute format('create policy "manager_delete_%1$s" on %1$s for delete using (is_manager());', t);
  end loop;
end $$;

drop policy if exists "staff_select_suppliers" on suppliers;
drop policy if exists "manager_write_suppliers" on suppliers;
create policy "staff_select_suppliers" on suppliers for select using (is_staff());
create policy "manager_write_suppliers" on suppliers for all using (is_manager()) with check (is_manager());

drop policy if exists "self_select_app_users" on app_users;
drop policy if exists "manager_write_app_users" on app_users;
drop policy if exists "manager_update_app_users" on app_users;
drop policy if exists "manager_delete_app_users" on app_users;
create policy "self_select_app_users" on app_users for select using (auth_user_id = auth.uid() or is_manager());
create policy "manager_write_app_users" on app_users for insert with check (is_manager());
create policy "manager_update_app_users" on app_users for update using (is_manager()) with check (is_manager());
create policy "manager_delete_app_users" on app_users for delete using (is_manager());

-- ============================================================================
-- 17. RPC: bootstrap_first_owner
-- ============================================================================
create or replace function bootstrap_first_owner(p_name text, p_pin text)
returns uuid
language plpgsql security definer as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'ต้องเข้าสู่ระบบก่อนตั้งค่าเจ้าของร้าน';
  end if;
  if exists (select 1 from app_users where role = 'OWNER') then
    raise exception 'มี OWNER อยู่แล้ว';
  end if;

  insert into app_users (id, auth_user_id, name, pin, role, permissions, is_active)
  values (gen_random_uuid(), auth.uid(), p_name, p_pin, 'OWNER', '["ALL"]'::jsonb, true)
  returning id into new_id;

  return new_id;
end;
$$;

-- ============================================================================
-- 18. RPC: create_sale
-- ============================================================================
create or replace function create_sale(
  p_bill_number     text,
  p_customer_id     uuid,
  p_user_id         uuid,
  p_shift_id        text,
  p_discount_amount numeric,
  p_tax_amount      numeric,
  p_payment_method  text,
  p_items           jsonb
) returns jsonb
language plpgsql security definer as $$
declare
  v_bill_id   uuid := gen_random_uuid();
  v_subtotal  numeric := 0;
  v_total     numeric;
  v_item      jsonb;
  v_variant   product_variants%rowtype;
  v_ratio     numeric;
  v_deduct    numeric;
  v_customer  customers%rowtype;
  v_shift_uuid uuid;
begin
  if not is_staff() then
    raise exception 'ไม่มีสิทธิ์บันทึกการขาย';
  end if;

  v_shift_uuid := nullif(p_shift_id, '')::uuid;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal + ((v_item->>'quantity')::numeric * (v_item->>'unit_price')::numeric);
  end loop;
  v_total := v_subtotal - coalesce(p_discount_amount, 0) + coalesce(p_tax_amount, 0);

  if upper(coalesce(p_payment_method,'CASH')) = 'CREDIT' and p_customer_id is not null then
    select * into v_customer from customers where id = p_customer_id for update;
    if found and (v_customer.debt + v_total) > v_customer.credit_limit then
      raise exception 'ยอดหนี้รวมจะเกินวงเงินเครดิตที่กำหนดไว้ (วงเงิน % หนี้เดิม % ยอดนี้ %)',
        v_customer.credit_limit, v_customer.debt, v_total;
    end if;
    if found then
      update customers set debt = debt + v_total where id = p_customer_id;
    end if;
  end if;

  insert into bills (id, bill_number, customer_id, user_id, shift_id, subtotal,
                      discount_amount, tax_amount, total, payment_method, status, created_at)
  values (v_bill_id, p_bill_number, p_customer_id, p_user_id, v_shift_uuid, v_subtotal,
          coalesce(p_discount_amount,0), coalesce(p_tax_amount,0), v_total,
          coalesce(p_payment_method,'CASH'), 'PAID', now());

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into bill_items (id, bill_id, product_id, variant_id, fraction_id,
                             item_name, quantity, unit_price, line_total)
    values (
      gen_random_uuid(), v_bill_id,
      nullif(v_item->>'product_id','')::uuid,
      nullif(v_item->>'variant_id','')::uuid,
      nullif(v_item->>'fraction_id','')::uuid,
      v_item->>'item_name',
      (v_item->>'quantity')::numeric,
      (v_item->>'unit_price')::numeric,
      (v_item->>'quantity')::numeric * (v_item->>'unit_price')::numeric
    );

    if nullif(v_item->>'variant_id','') is not null then
      select * into v_variant from product_variants
        where id = (v_item->>'variant_id')::uuid for update;

      if nullif(v_item->>'fraction_id','') is not null then
        select quantity_ratio into v_ratio from product_fractions
          where id = (v_item->>'fraction_id')::uuid;
        v_deduct := (v_item->>'quantity')::numeric / coalesce(v_ratio, 1);
      else
        v_deduct := (v_item->>'quantity')::numeric;
      end if;

      if found and v_variant.stock_quantity - v_deduct < 0 then
        raise exception 'สินค้า "%" คงเหลือไม่พอ (คงเหลือ % ต้องการหัก %)',
          v_item->>'item_name', v_variant.stock_quantity, v_deduct;
      end if;

      update product_variants set stock_quantity = stock_quantity - v_deduct
        where id = v_variant.id;

      insert into inventory_movements (variant_id, change_qty, reason, ref_type, ref_id)
      values (v_variant.id, -v_deduct, 'SALE', 'bill', v_bill_id);
    end if;
  end loop;

  return jsonb_build_object('bill_id', v_bill_id);
end;
$$;

-- ============================================================================
-- 19. RPC OTHER FUNCTIONS (receive_po, return, payment, adjust_stock)
-- ============================================================================
create or replace function receive_purchase_order(
  p_purchase_order_id uuid,
  p_items             jsonb
) returns void
language plpgsql security definer as $$
declare
  v_item    jsonb;
  v_poi     purchase_order_items%rowtype;
  v_new_recv numeric;
begin
  if not is_manager() then
    raise exception 'ต้องเป็นผู้จัดการขึ้นไปจึงจะรับสินค้าเข้าคลังได้';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    select * into v_poi from purchase_order_items
      where id = (v_item->>'purchase_order_item_id')::uuid for update;

    if not found then
      raise exception 'ไม่พบรายการสั่งซื้อ id=%', v_item->>'purchase_order_item_id';
    end if;

    v_new_recv := v_poi.received_quantity + (v_item->>'received_quantity')::numeric;
    if v_new_recv > v_poi.quantity then
      raise exception 'รับสินค้าเกินจำนวนที่สั่ง (สั่ง % แต่รับรวมแล้ว %)', v_poi.quantity, v_new_recv;
    end if;

    update purchase_order_items set received_quantity = v_new_recv where id = v_poi.id;

    if v_poi.variant_id is not null then
      update product_variants
        set stock_quantity = stock_quantity + (v_item->>'received_quantity')::numeric
        where id = v_poi.variant_id;

      insert into inventory_movements (variant_id, change_qty, reason, ref_type, ref_id)
      values (v_poi.variant_id, (v_item->>'received_quantity')::numeric,
              'PURCHASE_RECEIPT', 'purchase_order', p_purchase_order_id);
    end if;
  end loop;

  update purchase_orders set status = 'RECEIVED', received_at = now()
    where id = p_purchase_order_id
      and not exists (
        select 1 from purchase_order_items
        where purchase_order_id = p_purchase_order_id
          and received_quantity < quantity
      );
end;
$$;

create or replace function process_return(
  p_bill_id     uuid,
  p_items       jsonb,
  p_full_return boolean
) returns jsonb
language plpgsql security definer as $$
declare
  v_item        jsonb;
  v_variant     product_variants%rowtype;
  v_ratio       numeric;
  v_restock     numeric;
  v_bill        bills%rowtype;
  v_refund_total numeric := 0;
begin
  if not is_staff() then
    raise exception 'ไม่มีสิทธิ์บันทึกการคืนสินค้า';
  end if;

  select * into v_bill from bills where id = p_bill_id for update;
  if not found then
    raise exception 'ไม่พบบิล id=%', p_bill_id;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_refund_total := v_refund_total
      + (v_item->>'quantity')::numeric * (v_item->>'unit_price')::numeric;

    if nullif(v_item->>'variant_id','') is not null then
      select * into v_variant from product_variants
        where id = (v_item->>'variant_id')::uuid for update;

      if found then
        if nullif(v_item->>'fraction_id','') is not null then
          select quantity_ratio into v_ratio from product_fractions
            where id = (v_item->>'fraction_id')::uuid;
          v_restock := (v_item->>'quantity')::numeric / coalesce(v_ratio, 1);
        else
          v_restock := (v_item->>'quantity')::numeric;
        end if;

        update product_variants set stock_quantity = stock_quantity + v_restock
          where id = v_variant.id;

        insert into inventory_movements (variant_id, change_qty, reason, ref_type, ref_id)
        values (v_variant.id, v_restock, 'RETURN', 'bill', p_bill_id);
      end if;
    end if;
  end loop;

  if p_full_return then
    update bills set status = 'CANCELLED' where id = p_bill_id;
  end if;

  if upper(v_bill.payment_method) = 'CREDIT' and v_bill.customer_id is not null then
    update customers set debt = greatest(0, debt - v_refund_total) where id = v_bill.customer_id;
  else
    insert into cash_ledger (shift_id, type, income, expense, description, ref_id)
    values (v_bill.shift_id, 'expense-refund', 0, v_refund_total, 'คืนสินค้าบิล ' || v_bill.bill_number, p_bill_id::text);
  end if;

  return jsonb_build_object('refund_total', v_refund_total);
end;
$$;

create or replace function receive_customer_payment(
  p_customer_id uuid,
  p_amount      numeric,
  p_shift_id    uuid
) returns jsonb
language plpgsql security definer as $$
declare
  v_customer customers%rowtype;
  v_applied  numeric;
begin
  if not is_staff() then
    raise exception 'ไม่มีสิทธิ์บันทึกการรับชำระหนี้';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'จำนวนเงินที่รับชำระต้องมากกว่า 0';
  end if;

  select * into v_customer from customers where id = p_customer_id for update;
  if not found then
    raise exception 'ไม่พบลูกค้า id=%', p_customer_id;
  end if;

  v_applied := least(p_amount, v_customer.debt);

  update customers set debt = debt - v_applied where id = p_customer_id;

  insert into cash_ledger (shift_id, type, income, expense, description, ref_id)
  values (p_shift_id, 'cash-in-ar', v_applied, 0, 'รับชำระหนี้จาก ' || v_customer.name, p_customer_id::text);

  return jsonb_build_object('applied', v_applied, 'remaining_debt', v_customer.debt - v_applied);
end;
$$;

create or replace function adjust_stock(
  p_variant_id uuid,
  p_mode       text,
  p_value      numeric,
  p_reason     text default null
) returns jsonb
language plpgsql security definer as $$
declare
  v_variant  product_variants%rowtype;
  v_new      numeric;
  v_change   numeric;
begin
  if not is_manager() then
    raise exception 'เฉพาะผู้จัดการขึ้นไปเท่านั้นที่ปรับจำนวนสต็อกด้วยมือได้';
  end if;
  if p_mode not in ('SET', 'DELTA') then
    raise exception 'p_mode ต้องเป็น SET หรือ DELTA เท่านั้น';
  end if;

  select * into v_variant from product_variants where id = p_variant_id for update;
  if not found then
    raise exception 'ไม่พบสินค้า variant id=%', p_variant_id;
  end if;

  v_new := case when p_mode = 'SET' then greatest(0, p_value)
                else greatest(0, v_variant.stock_quantity + p_value) end;
  v_change := v_new - v_variant.stock_quantity;

  update product_variants set stock_quantity = v_new where id = p_variant_id;

  if v_change <> 0 then
    insert into inventory_movements (variant_id, change_qty, reason, ref_type, ref_id)
    values (p_variant_id, v_change, 'ADJUSTMENT', 'manual', null);
  end if;

  return jsonb_build_object('variant_id', p_variant_id, 'new_stock', v_new, 'change', v_change);
end;
$$;

-- ============================================================================
-- 20. STORAGE BUCKETS & RLS
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('delivery-notes', 'delivery-notes', false)
on conflict (id) do nothing;

drop policy if exists "public_read_product_images" on storage.objects;
drop policy if exists "staff_write_product_images" on storage.objects;
drop policy if exists "staff_update_product_images" on storage.objects;
drop policy if exists "staff_delete_product_images" on storage.objects;

create policy "public_read_product_images" on storage.objects for select using (bucket_id = 'product-images');
create policy "staff_write_product_images" on storage.objects for insert with check (bucket_id = 'product-images' and is_staff());
create policy "staff_update_product_images" on storage.objects for update using (bucket_id = 'product-images' and is_staff());
create policy "staff_delete_product_images" on storage.objects for delete using (bucket_id = 'product-images' and is_staff());

drop policy if exists "staff_read_delivery_notes" on storage.objects;
drop policy if exists "staff_write_delivery_notes" on storage.objects;
drop policy if exists "staff_delete_delivery_notes" on storage.objects;

create policy "staff_read_delivery_notes" on storage.objects for select using (bucket_id = 'delivery-notes' and is_staff());
create policy "staff_write_delivery_notes" on storage.objects for insert with check (bucket_id = 'delivery-notes' and is_staff());
create policy "staff_delete_delivery_notes" on storage.objects for delete using (bucket_id = 'delivery-notes' and is_staff());
