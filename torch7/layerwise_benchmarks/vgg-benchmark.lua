require 'sys'
require 'cunn'
require 'ccn2'
require 'cudnn'

print('Running on device: ' .. cutorch.getDeviceProperties(cutorch.getDevice()).name)

steps = 4 -- nb of steps in loop to average perf

runs = {
   {
      -- first layer
      ni = 3,
      no = 64,
      kw = 3,
      kh = 3,
      iw = 224,
      ih = 224,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 64,
      no = 64,
      kw = 3,
      kh = 3,
      iw = 224,
      ih = 224,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 64,
      no = 128,
      kw = 3,
      kh = 3,
      iw = 112,
      ih = 112,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 128,
      no = 128,
      kw = 3,
      kh = 3,
      iw = 112,
      ih = 112,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 128,
      no = 256,
      kw = 3,
      kh = 3,
      iw = 56,
      ih = 56,
      bs = 64,
      dw = 1,
      dh = 1,
   },

   {
      ni = 256,
      no = 256,
      kw = 3,
      kh = 3,
      iw = 56,
      ih = 56,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 256,
      no = 512,
      kw = 3,
      kh = 3,
      iw = 28,
      ih = 28,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 512,
      no = 512,
      kw = 3,
      kh = 3,
      iw = 28,
      ih = 28,
      bs = 64,
      dw = 1,
      dh = 1,
   },
   {
      ni = 512,
      no = 512,
      kw = 3,
      kh = 3,
      iw = 14,
      ih = 14,
      bs = 64,
      dw = 1,
      dh = 1,
   }
}


for i,run in ipairs(runs) do
   -- params for run:
   local ni,no,kw,kh,bs,iw,ih,dw,dh = run.ni,run.no,run.kw,run.kh,run.bs,run.iw,run.ih,run.dw,run.dh
   print('')
   print('CONFIG: input = ' .. ni..'x'..iw..'x'..ih..' * ker = ' .. ni..'x'..no..'x'..kw..'x'..kh .. ' (bs = '..bs..', stride = ' .. dw .. ')')
   local mods = {}
   mods[1] = cudnn.SpatialConvolution(ni,no,kw,kh,dw,dh, 1, 1):cuda()
   mods[2] = nn.SpatialConvolutionMM(ni,no,kw,kh,dw,dh):cuda(); mods[2].padding = 1
   mods[3] = ccn2.SpatialConvolution(ni,no,kw,dw):cuda()
   for j=1,#mods do   
      local tmf, tmbi, tmbg
      collectgarbage()
      if torch.typename(mods[j]) == 'ccn2.SpatialConvolution' then
         i1 = torch.randn(ni, ih, iw, bs):cuda();
      else
         i1 = torch.randn(bs, ni, ih, iw):cuda()
      end         
      collectgarbage()
      local o1 = mods[j]:forward(i1)
      cutorch.synchronize()
      collectgarbage()
      sys.tic()
      for t = 1,steps do
         o1 = mods[j]:updateOutput(i1)
      end
      cutorch.synchronize()
      tmf = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", torch.typename(mods[j]), ':updateOutput():', tmf*1000))

      cutorch.synchronize()
      collectgarbage()
      sys.tic()
      for t = 1,steps do
         mods[j]:updateGradInput(i1, o1)
      end
      cutorch.synchronize()
      tmbi = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", torch.typename(mods[j]), ':updateGradInput():', tmbi*1000))

      cutorch.synchronize()
      collectgarbage()
      sys.tic()
      local ok = 1
      for t = 1,steps do
         ok = pcall(function() mods[j]:accGradParameters(i1, o1) end)
      end
      cutorch.synchronize()
      tmbg = sys.toc()/steps
      if not ok then
         print(string.format("%-30s %25s %s", torch.typename(mods[j]), ':accGradParameters():', 'FAILED!'))
      else
         print(string.format("%-30s %25s %10.2f", torch.typename(mods[j]), ':accGradParameters():', tmbg*1000))
      end
      print(string.format("%-30s %25s %10.2f", torch.typename(mods[j]), ':TOTAL:', (tmf+tmbi+tmbg)*1000))
      print()
   end
end

print('')
