-- Trazabilidad: usuario que registró cada compra (co-propietarios)
ALTER TABLE public.compras
  ADD COLUMN IF NOT EXISTS created_by_user_id UUID
    REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_compras_created_by
  ON public.compras(created_by_user_id);

-- Reutiliza la función de schema_3g (autopoblar con auth.uid() si falta).
DROP TRIGGER IF EXISTS compras_autor ON public.compras;
CREATE TRIGGER compras_autor
  BEFORE INSERT ON public.compras
  FOR EACH ROW EXECUTE FUNCTION public.autopopular_tarea_autor();
