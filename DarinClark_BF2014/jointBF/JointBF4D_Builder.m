%% Build the jointBF object code
% adds separable resampling kernel

cd C:\Users\DPC\Dropbox\GPU_Recon_Toolkit_v5\jointBF_4D_v2;
% cuda_helper_includes = 'C:\ProgramData\NVIDIA Corporation\CUDA Samples\v6.0\common\inc';
mex_inculdes = 'C:\Program Files\MATLAB\R2014a\extern\include';
% recon_includes = 'D:\Recon\include';

c_comp_path = 'C:\Program Files (x86)\Microsoft Visual Studio 11.0\VC\bin';
compute = '35';

cmd = ['nvcc -c jointBF4D_cuda.cu -ccbin "' c_comp_path '" -arch=sm_' compute ' -I"' mex_inculdes '" --ptxas-options=-v'];

system(cmd);

%% Compile C program w/ mex interface and ignored libraries

cd C:\Users\DPC\Dropbox\GPU_Recon_Toolkit_v5\jointBF_4D_v2;

clear mex;

cuda_libraries = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v6.0\lib\x64';
cuda_includes = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v6.0\include';

ignore = '';
ignores = {'libc.lib', 'msvcrt.lib', 'libcd.lib', 'libcmtd.lib', 'msvcrtd.lib'};

for i = 1:length(ignores)
   
    ignore = [ignore '/NODEFAULTLIB:' ignores{i} ' '];
    
end

cmd = ['mex -largeArrayDims jointBF4D.cpp jointBF4D_cuda.obj -lcudart -L"' cuda_libraries '" -I"' cuda_includes '" ' ignore];

% for debugging in Visual Studio...
% -largeArrayDims option ... use size_t instead of int sizes
% -g option ... enable debugging
% cmd = ['mex -largeArrayDims -g jointBF4D.cpp jointBF4D_cuda.obj -lcudart -L"' cuda_libraries '" -I"' cuda_includes '" ' ignore];

system(cmd);

%% Test code

cd C:\Users\DPC\Dropbox\GPU_Recon_Toolkit_v5\Functions;

sz = [256 256 256];
w = 6;
w2 = 1.2;
q = 2*w;
m = 2.5;
sig = 0.1;

A_ = make_A_approx_3D_v2(w,w2);

X = zeros(sz,'single'); % GPU 1D texture size limit: 2^27 (i.e. 512^3)
X1 = X; X2 = X;

X1(32:end,:,:) = 0.1;
X2(32:end,:,:) = 1;

X1 = X1 + sig*randn(size(X1));
X2 = X2 + sig*randn(size(X2));

c = -1/(2*m*m*sig*sig)

%%

clear mex;
clear jointBF4D;
reset(gpuDevice(1));
reset(gpuDevice(2));

%% Test 3D, single volume
% X, nvols, ntimes, A, At, s, w, m

At = [1];

X = single(X1(:));
nvols = int32(1);
ntimes = int32(1);
A_in = single(A_);
At_in = single(At);
sz_in = int32(sz);
w_in = int32(w);
m_in = single(m);

tic;
[Xf,noise,flag] = jointBF4D(X,nvols,ntimes,A_in,At_in,sz_in,w_in,m_in);
toc;

Xf = reshape(Xf,[sz(1) sz(2) sz(3)]);
imtool(mat2gray(Xf(:,:,w+1)));

%% Test 3D, joint

At = [1];

X = single(cat(2,X1(:),X2(:)));
nvols = int32(2);
ntimes = int32(1);
A_in = single(A_);
At_in = single(At);
sz_in = int32(sz);
w_in = int32(w);
m_in = single(m);

tic;
[Xf_joint,noise,flag] = jointBF4D(X,nvols,ntimes,A_in,At_in,sz_in,w_in,m_in);
toc;

Xf_joint = reshape(Xf_joint,[sz(1) sz(2) sz(3) 2]);

imtool(mat2gray([Xf(:,:,w+1) Xf_joint(:,:,w+1,1) Xf_joint(:,:,w+1,2)]));

%% Test 4D

X1 = zeros(sz) + 0.2 + 0.05*randn(sz);
X2 = zeros(sz) + 1 + 0.05*randn(sz);
X3 = zeros(sz) + 0.7 + 0.1*randn(sz);

At = [0.2 0.6 0.2];

X = single(cat(2,X1(:),X2(:),X3(:)));
nvols = int32(1);
ntimes = int32(3);
A_in = single(A_);
At_in = single(At);
sz_in = int32(sz);
w_in = int32(w);
m_in = single(m);

tic;
[Xf_joint,noise,flag] = jointBF4D(X,nvols,ntimes,A_in,At_in,sz_in,w_in,m_in);
toc;

Xf_joint = reshape(Xf_joint,sz);

figure(1); hold on;
imagesc([Xf_joint(:,:,w+1) X1(:,:,w+1) X2(:,:,w+1) X3(:,:,w+1)],[0 1]);
axis image off; colormap gray;

%% Compute expected result

% a = sum([0.2 1 0.7].*[0.2 0.6 0.2]);
a = sum([1 1 0.1].*[0.2 0.6 0.2]);

R1 = exp(-(X1(:)-a).^2./(2*m*m*0.05*0.05));
R2 = exp(-(X2(:)-a).^2./(2*m*m*0.05*0.05));
R3 = exp(-(X3(:)-a).^2./(2*m*m*0.1*0.1));

expected_val = sum(X1(:).*R1+X2(:).*R2+X3(:).*R3)./sum(R1+R2+R3)

%%

clear mex;
clear jointBF4D;
reset(gpuDevice(1));
reset(gpuDevice(2));

%% Test 4D, joint

X0 = zeros(sz) + 1 + 0.01*randn(sz);
X1 = zeros(sz) + 1 + 0.05*randn(sz);
X2 = zeros(sz) + 1 + 0.05*randn(sz);
X3 = zeros(sz) + 0.1 + 0.1*randn(sz);

At = [0.2 0.6 0.2];

X = single(cat(2,X0(:),X1(:),X0(:),X2(:),X0(:),X3(:)));
nvols = int32(2);
ntimes = int32(3);
A_in = single(A_);
At_in = single(At);
sz_in = int32(sz);
w_in = int32(w);
m_in = single(m);

tic;
[Xf_joint,noise,flag] = jointBF4D(X,nvols,ntimes,A_in,At_in,sz_in,w_in,m_in);
toc;

Xf_joint = reshape(Xf_joint,[sz(1) sz(2) sz(3) 2]);

figure(1); hold on;
imagesc([Xf_joint(:,:,w+1,1) Xf_joint(:,:,w+1,2) X0(:,:,w+1) X1(:,:,w+1) X2(:,:,w+1) X3(:,:,w+1)],[0 1]);
axis image off; colormap gray;